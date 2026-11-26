# 编译与发布说明

每次编译都用 `scripts/mnote_release.sh` 打包，在 h3c-4s-03 的 `~/mnote-builds/<编译编号>/` 生成一个独立目录：

```
mnote-<日期>-<时间>-<commit>-<debug|release>/
  mNote-<编译编号>.apk
  RELEASE_NOTES.md   本次改进 + 本次测试范围 + 提交记录
  manifest.json      包名、版本、commit、APK SHA-256、自动化检查结果
  testcases/         真机测试用例（给 adb 测试 Agent）、测试素材、参考截图、结果模板
  analyze.log / unit-tests.log / build.log
```

## 流程
1. 改代码时，同步把说明写进 `docs/releases/UNRELEASED.md`，并更新 `testing/device/` 里对应的用例。
2. 提交后在 h3c-4s-03 上运行：
   ```bash
   cd ~/mNote
   export https_proxy=http://proxy.ims.intel.com:911 http_proxy=$https_proxy no_proxy=localhost,127.0.0.1
   scripts/mnote_release.sh debug        # 或 release
   git push
   ```
   脚本会先跑 `flutter analyze` 和 `flutter test test/mnote`，失败就不打包。
3. 脚本把本次说明存为 `docs/releases/<编译编号>.md`，在 `index.md` 记一行，并把 `UNRELEASED.md` 重置为模板。
4. 编译目录同步到本机 `~/projects/mNote/builds/<编译编号>/`，交给测试 Agent。

## 编译记录
见 [index.md](index.md)。
