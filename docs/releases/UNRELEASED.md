> 用例修正：TC-MAP-02 前置条件、TC-INK-03 改为人工；新增人工检查清单

# 本次改进

本编译与上一编译代码相同，只修改测试用例。

## 用例调整
- TC-MAP-02：写明前置条件——需要第 3 页的红色卡片，没有时先按 TC-EXC-06 创建（上一轮测试反馈）。
- TC-INK-03：改为「人工」用例，测试 Agent 不执行、不计入跳过（adb 不能可靠注入双指缩放）。
- 新增 `testcases/MANUAL_CHECKS.md`：需要真实触控笔 / 手指的 6 项人工检查（压感、延迟、防误触、缩放后笔迹位置、橡皮端、布局 v2 手感）。
- 上一轮反馈的 TC-EXC-04「第 2 页右栏」描述错误，已在布局 v2 改写的用例中去掉（该句实际在左栏）。

## 已知问题
- 同上一编译。

# 本次测试范围
- 同上一编译：布局 v2 必测用例（TC-READ-01、TC-EXC-01、TC-EXC-04、TC-EXC-05、TC-EXC-07、TC-MAP-01、TC-MAP-02、TC-MAP-03、TC-RECALL-01、TC-UI-02、TC-UI-03、TC-INK-01、TC-INK-07、TC-INK-10）；TC-MAP-SETUP 及 TC-MAP-04 至 TC-MAP-14；冒烟用例。
- **人工**：MANUAL_CHECKS.md（由人执行）。
- **不测**：Nextcloud 同步；KNOWN_ISSUES.md 中的不修复项；同级排序、新建空节点（未实现）。
