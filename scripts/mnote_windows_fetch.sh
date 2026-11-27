#!/usr/bin/env bash
# Download the mNote Windows build of a commit from GitHub Actions into
# ~/projects/mNote/builds/<name>/ (installer + portable zip + notes).
#
# Usage: scripts/mnote_windows_fetch.sh [commit-sha|branch]   (default: m6-windows)
# Needs: gh (logged in; read access to the public repo is enough).
set -euo pipefail

REPO=cnwuzhh/mNote
REF=${1:-m6-windows}
OUT_ROOT=${MNOTE_BUILDS:-$HOME/projects/mNote/builds}

# Newest "mNote Windows" run for the ref (branch name or commit).
if [[ $REF =~ ^[0-9a-f]{7,40}$ ]]; then
  RUN=$(gh run list -R $REPO -w "mNote Windows" -L 30 --json databaseId,headSha,status,conclusion \
    --jq "[.[] | select(.headSha | startswith(\"$REF\"))][0]")
else
  RUN=$(gh run list -R $REPO -w "mNote Windows" -b "$REF" -L 1 --json databaseId,headSha,status,conclusion --jq '.[0]')
fi
[[ -n $RUN && $RUN != null ]] || { echo "no mNote Windows run for $REF" >&2; exit 1; }
ID=$(jq -r .databaseId <<<"$RUN"); SHA=$(jq -r .headSha <<<"$RUN")
STATUS=$(jq -r .status <<<"$RUN"); CONCL=$(jq -r .conclusion <<<"$RUN")
echo "run $ID for ${SHA::8}: $STATUS ${CONCL}"
if [[ $STATUS != completed ]]; then
  echo "waiting for the run to finish…"
  gh run watch "$ID" -R $REPO --exit-status --interval 30 >/dev/null
fi
[[ $(gh run view "$ID" -R $REPO --json conclusion --jq .conclusion) == success ]] || { echo "run $ID did not succeed" >&2; exit 1; }

NAME=$(gh api "repos/$REPO/actions/runs/$ID/artifacts" --jq '.artifacts[0].name')
DEST="$OUT_ROOT/$NAME"
mkdir -p "$DEST"
gh run download "$ID" -R $REPO -n "$NAME" -D "$DEST"
(cd "$DEST" && sha256sum ./*.exe ./*.zip > SHA256SUMS)
cat > "$DEST/README.md" <<EOF
# $NAME

- Commit: $SHA (https://github.com/$REPO/commit/$SHA)
- Built by GitHub Actions run https://github.com/$REPO/actions/runs/$ID
- \`*-installer.exe\`: installs mNote for Windows (x64); optionally installs the Visual C++ runtime.
- \`*-portable.zip\`: unzip anywhere and run \`mnote.exe\` (needs the Visual C++ runtime, usually already present).
- The files are not code-signed: Windows SmartScreen shows "Windows protected your PC" — choose "More info" → "Run anyway".
EOF
cp "$(dirname "$0")/../testing/device/cases/TC-80-windows.md" "$DEST/TESTCASES.md" 2>/dev/null || true
echo "downloaded to $DEST"
ls -l "$DEST"

# Publish next to the tablet builds on the build server, where the test agent
# looks: /home/johnson/mnote-builds/windows/<name>/ and windows/LATEST.
HOST=${MNOTE_BUILD_HOST:-h3c-4s-03}
ssh "$HOST" 'mkdir -p ~/mnote-builds/windows'
rsync -a "$DEST" "$HOST:mnote-builds/windows/"
ssh "$HOST" "cd ~/mnote-builds/windows && ln -sfn '$NAME' LATEST && cd '$NAME' && sha256sum -c --quiet SHA256SUMS && echo published to \$HOST:~/mnote-builds/windows/$NAME '(windows/LATEST)'"
