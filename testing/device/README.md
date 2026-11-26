# mNote 真机测试说明（给 adb 测试 Agent）

每个编译目录里都有：

```
<build-id>/
  <build-id>.apk     要测试的安装包
  RELEASE_NOTES.md         这次改了什么、这次要重点测什么（必读）
  manifest.json            包名、版本、commit、SHA-256
  testcases/
    README.md              本文件
    INDEX.md               全部用例清单
    cases/TC-*.md          用例
    assets/                测试素材（论文 PDF 等）
    reference/             参考截图（期望界面大致长这样）
    RESULTS_TEMPLATE.md    结果报告模板
    KNOWN_ISSUES.md 已知问题和不修复项（遇到不必报告）
    MANUAL_CHECKS.md 人工检查（真实笔 / 手指），测试 Agent 不执行
```

## 1. 跑哪些用例
看 `RELEASE_NOTES.md` 里的「本次测试范围」：
- **必测**：这次新增或改动的功能对应的用例。
- **回归**：冒烟用例（INDEX 里标 `冒烟` 的）每次都跑。
- 时间允许再跑其余用例。

## 2. 准备

```bash
APK=<build-id>.apk
PKG=io.github.cnwuzhh.mnote
adb devices                                   # 确认设备在线
adb uninstall $PKG || true                    # 每次从干净状态开始（除非用例要求保留数据）
adb uninstall com.adilhanney.saber || true    # 旧的测试包（包名不同，是另一个 App）
adb install -r "$APK"
adb push testcases/assets/arxiv-2610.18579v1.pdf /sdcard/Download/
adb shell settings put system accelerometer_rotation 0   # 关自动旋转
adb shell settings put system user_rotation 1            # 横屏（用例要求竖屏时改成 0）
adb shell am start -n $PKG/.MainActivity                 # 启动
```

## 3. 找界面元素
mNote 是 Flutter 应用，界面会暴露给无障碍树，`uiautomator` 能看到：
- 按钮、标签上的**文字**（`text`），例如「新建学习集」「摘录为卡片」「框选」。
- 图标按钮的**提示文字**（`content-desc`），例如「目录」「搜索」「夜读」「收起脑图」「展开脑图」「返回」「回到原文 p.1」，以及摘录颜色「定义」「实验证据」「应用」「易错」。

```bash
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml
# 在 ui.xml 里按 text / content-desc 找节点，取 bounds="[x1,y1][x2,y2]" 的中心点击
adb shell input tap X Y
adb shell input text 'Agent'                  # 中文输入用剪贴板或 ADBKeyboard，见下
adb shell input swipe X Y X Y 900             # 原地长按 900 ms
adb shell input swipe X1 Y1 X2 Y2 600         # 拖动（拖选区手柄、拖脑图卡片前先长按）
```

**PDF 正文不在无障碍树里。** 要在 PDF 上长按选字时：先截图，在截图里找到用例写的那句话的位置，再按截图像素坐标长按。设备截图像素就是 `input` 用的坐标。

**输入中文**：`adb shell input text` 不支持中文。可以装 ADBKeyboard（`adb shell am broadcast -a ADB_INPUT_TEXT --es msg '中文'`），或者用例里允许时改用英文名字。

## 4. 证据
每个用例都要留：
- 每个关键步骤一张截图：`adb exec-out screencap -p > <TC-ID>_<步骤号>.png`
- 整个用例期间的日志：开始前 `adb logcat -c`，结束后 `adb logcat -d > <TC-ID>_logcat.txt`
- Flutter 报错看日志里的 `flutter` 标签：`adb logcat -d -s flutter`；出现 `EXCEPTION CAUGHT`、`RenderFlex overflowed`、`Unhandled Exception` 都算失败，即使界面看上去正常。
- debug 包可以看 App 数据：`adb shell run-as $PKG ls -R app_flutter`（笔记在 `app_flutter/mNote/`，学习集在 `files/mnote/` 下）

## 5. 判定
- **通过**：每一步的「期望」都满足，日志里没有上面那几类报错。
- **失败**：任意一步不满足；写清楚是哪一步、看到了什么、截图文件名。
- **阻塞**：前置步骤失败导致无法继续（例如导入 PDF 失败，后面的摘录都测不了）。
- **跳过**：设备不支持或本次不在范围内，写明原因。
- 用例写得不清楚、或期望本身看起来不合理时，照实记录「用例问题」，不要自己改判。
- `KNOWN_ISSUES.md` 里「不修复」的问题再遇到时不必报告。
- 标 `人工` 的用例（如 TC-INK-03）和 `MANUAL_CHECKS.md` 由人执行，测试 Agent 不执行，也不计入「跳过」。

## 6. 报告
复制 `RESULTS_TEMPLATE.md` 填写，和截图、日志放在同一个文件夹里交回。
