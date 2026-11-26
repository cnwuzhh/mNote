#!/usr/bin/env bash
# Build mNote and package one self-contained directory per build:
#
#   $MNOTE_BUILDS_DIR/<build-id>/
#     <build-id>.apk
#     RELEASE_NOTES.md     header + docs/releases/UNRELEASED.md + commit list
#     manifest.json        package, version, commit, sha256, checks
#     testcases/           testing/device/* + assets/ (sample PDFs) + reference/ (screenshots)
#     results/             empty; the test agent writes its report here
#
# Also keeps $MNOTE_BUILDS_DIR/README.md (agent handoff), LATEST -> newest
# build, and BUILDS.md (copy of docs/releases/index.md) up to date.
#
# Afterwards the notes are archived to docs/releases/<build-id>.md, a row is
# added to docs/releases/index.md, UNRELEASED.md is reset, and these files
# are committed (not pushed).
#
# Usage: scripts/mnote_release.sh [debug|release] [--allow-dirty] [--skip-tests]
set -euo pipefail
export TZ=${MNOTE_TZ:-Asia/Shanghai}   # build ids and timestamps in Beijing time

TYPE=debug
ALLOW_DIRTY=0
SKIP_TESTS=0
for arg in "$@"; do
  case "$arg" in
    debug|release) TYPE=$arg ;;
    --allow-dirty) ALLOW_DIRTY=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
BUILDS_DIR=${MNOTE_BUILDS_DIR:-$HOME/mnote-builds}
PKG=io.github.cnwuzhh.mnote
BT=$(ls -d "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/* | sort -V | tail -1)

if [[ $ALLOW_DIRTY == 0 && -n "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "Working tree has uncommitted changes; commit them first (or pass --allow-dirty)." >&2
  exit 1
fi
if [[ ! -s docs/releases/UNRELEASED.md ]] || grep -q '^<!-- empty -->' docs/releases/UNRELEASED.md; then
  echo "docs/releases/UNRELEASED.md has no notes for this build; fill it in first." >&2
  exit 1
fi

SHA=$(git rev-parse --short=8 HEAD)
BRANCH=$(git rev-parse --abbrev-ref HEAD)
STAMP=$(date +%Y%m%d-%H%M)
ID="mnote-${STAMP}-${SHA}-${TYPE}"
OUT="$BUILDS_DIR/$ID"
mkdir -p "$OUT/testcases"
echo "== build id: $ID"

# Previous packaged build = last row of docs/releases/index.md.
PREV_ID="" PREV_SHA=""
if [[ -f docs/releases/index.md ]]; then
  last=$(grep -E '^\| mnote-' docs/releases/index.md | tail -1 || true)
  if [[ -n "$last" ]]; then
    PREV_ID=$(echo "$last" | awk -F'|' '{gsub(/ /,"",$2); print $2}')
    PREV_SHA=$(echo "$last" | awk -F'|' '{gsub(/ /,"",$5); print $5}')
  fi
fi

# ---- automated checks ----
ANALYZE="skipped" TESTS="skipped"
if [[ $SKIP_TESTS == 0 ]]; then
  echo "== flutter analyze"
  if flutter analyze >"$OUT/analyze.log" 2>&1; then ANALYZE="passed"; else ANALYZE="FAILED"; fi
  echo "== flutter test test/mnote"
  if flutter test test/mnote >"$OUT/unit-tests.log" 2>&1; then
    TESTS="passed ($(grep -oE '\+[0-9]+' "$OUT/unit-tests.log" | tail -1 | tr -d +) tests)"
  else
    TESTS="FAILED"
  fi
  if [[ $ANALYZE == FAILED || $TESTS == FAILED ]]; then
    echo "Automated checks failed (see $OUT/*.log); not packaging." >&2
    exit 1
  fi
fi

# ---- build ----
echo "== flutter build apk --$TYPE"
flutter build apk "--$TYPE" --target-platform android-arm64 >"$OUT/build.log" 2>&1 || {
  echo "Build failed, see $OUT/build.log" >&2; exit 1; }
SRC_APK=build/app/outputs/flutter-apk/app-$TYPE.apk
[[ $TYPE == release ]] && SRC_APK=build/app/outputs/flutter-apk/app-release.apk
APK="$OUT/$ID.apk"
cp "$SRC_APK" "$APK"
APK_SHA=$(sha256sum "$APK" | cut -d' ' -f1)
BADGING=$("$BT/aapt2" dump badging "$APK" 2>/dev/null | awk 'NR==1' || true)
VNAME=$(echo "$BADGING" | sed -E "s/.*versionName='([^']*)'.*/\1/")
VCODE=$(echo "$BADGING" | sed -E "s/.*versionCode='([^']*)'.*/\1/")
SIGNER=$("$BT/apksigner" verify --print-certs "$APK" 2>/dev/null | awk -F'DN: ' '/certificate DN/ && !n {print $2; n=1}' || true)

# ---- test cases ----
cp -r testing/device/. "$OUT/testcases/"
mkdir -p "$OUT/testcases/assets" "$OUT/testcases/reference"
cp test/samples/usecases/*.pdf "$OUT/testcases/assets/" 2>/dev/null || true
cp test/mnote/screenshots/*.png "$OUT/testcases/reference/" 2>/dev/null || true

# ---- release notes ----
COMMITS=$( { if [[ -n "$PREV_SHA" ]] && git cat-file -e "$PREV_SHA" 2>/dev/null; then
              git log --no-merges --format='- `%h` %s' "$PREV_SHA..HEAD"
            else
              git log --no-merges --format='- `%h` %s' -n 30
            fi; } )
{
  echo "# mNote 编译 $ID"
  echo
  echo "| 项目 | 值 |"
  echo "|---|---|"
  echo "| 编译编号 | \`$ID\` |"
  echo "| 编译时间 | $(date '+%Y-%m-%d %H:%M %Z') |"
  echo "| 类型 | $TYPE（arm64-v8a） |"
  echo "| 分支 / commit | \`$BRANCH\` / \`$(git rev-parse HEAD)\` |"
  echo "| 上一个编译 | ${PREV_ID:-（无，这是第一个打包的编译）} |"
  echo "| 包名 / 版本 | \`$PKG\` / $VNAME（versionCode $VCODE） |"
  echo "| 签名 | $SIGNER |"
  echo "| APK SHA-256 | \`$APK_SHA\` |"
  echo "| 自动化检查 | analyze: $ANALYZE；单元/Widget 测试: $TESTS |"
  echo
  cat docs/releases/UNRELEASED.md
  echo
  echo "# 提交记录"
  echo
  echo "${COMMITS:-（无）}"
  echo
  echo "# 如何测试"
  echo
  echo "见 \`testcases/README.md\`（安装、找元素、留证据、判定规则）和 \`testcases/INDEX.md\`（用例清单）。结果按 \`testcases/RESULTS_TEMPLATE.md\` 填写。"
} >"$OUT/RELEASE_NOTES.md"

cat >"$OUT/manifest.json" <<JSON
{
  "buildId": "$ID",
  "buildType": "$TYPE",
  "builtAt": "$(date -Iseconds)",
  "package": "$PKG",
  "versionName": "$VNAME",
  "versionCode": $VCODE,
  "abi": "arm64-v8a",
  "branch": "$BRANCH",
  "commit": "$(git rev-parse HEAD)",
  "previousBuild": "${PREV_ID}",
  "apk": "$ID.apk",
  "apkSha256": "$APK_SHA",
  "signer": "$SIGNER",
  "checks": { "analyze": "$ANALYZE", "tests": "$TESTS" }
}
JSON

# ---- archive notes in the repo ----
cp "$OUT/RELEASE_NOTES.md" "docs/releases/$ID.md"
if [[ ! -f docs/releases/index.md ]]; then
  printf '# 编译记录\n\n| 编译编号 | 时间 | 类型 | commit | 说明 |\n|---|---|---|---|---|\n' >docs/releases/index.md
fi
# One-line summary: the first "> " line of the notes, else the first bullet;
# markdown stripped, cut to 40 characters (not bytes).
SUMMARY=$(python3 - <<'PY2'
import re
lines = open("docs/releases/UNRELEASED.md", encoding="utf-8").read().splitlines()
pick = next((l[2:] for l in lines if l.startswith("> ")), None) or next((l[2:] for l in lines if l.startswith("- ")), "")
pick = re.sub(r"[*`|]", "", pick).strip()
print(pick if len(pick) <= 40 else pick[:40] + "…")
PY2
)
echo "| $ID | $(date '+%Y-%m-%d %H:%M') | $TYPE | $SHA | [$SUMMARY]($ID.md) |" >>docs/releases/index.md
cp scripts/release_notes_template.md docs/releases/UNRELEASED.md
git add "docs/releases/$ID.md" docs/releases/index.md docs/releases/UNRELEASED.md
git -c user.name="${GIT_AUTHOR_NAME:-cnwuzhh}" -c user.email="${GIT_AUTHOR_EMAIL:-cnwuzhh@users.noreply.github.com}" \
  commit -q -m "release: notes for $ID"

# ---- entry points for the test agent ----
mkdir -p "$OUT/results"
cp testing/device/AGENT_HANDOFF.md "$BUILDS_DIR/README.md"
ln -sfn "$ID" "$BUILDS_DIR/LATEST"
# Links in index.md are <id>.md (repo layout); here notes live in <id>/RELEASE_NOTES.md.
sed -E 's#\]\((mnote-[^)]+)\.md\)#](\1/RELEASE_NOTES.md)#' docs/releases/index.md >"$BUILDS_DIR/BUILDS.md"

echo "== done: $OUT"
ls -la "$OUT"
