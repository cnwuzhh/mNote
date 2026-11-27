# mNote 编译 mnote-20261127-1443-babef43f-debug

| 项目 | 值 |
|---|---|
| 编译编号 | `mnote-20261127-1443-babef43f-debug` |
| 编译时间 | 2026-11-27 14:44 CST |
| 类型 | debug（arm64-v8a） |
| 分支 / commit | `m6-windows` / `babef43fb26377464efcc3930451a633b315b616` |
| 上一个编译 | mnote-20261127-1238-b74fb533-debug |
| 包名 / 版本 | `io.github.cnwuzhh.mnote` / 1.38.0（versionCode 138000） |
| 签名 | CN=mNote, O=cnwuzhh, C=CN |
| APK SHA-256 | `219d997ee81acbe23b1befffdb4d131230eb22b8ba66f856488c5795d1045c59` |
| 自动化检查 | analyze: passed；单元/Widget 测试: passed (81 tests) |

> 修复：Nextcloud 登录时「请授权」对话框出现了，但登录页没有打开

# 本次改进

## 修复
- **Nextcloud 登录页不打开**（用户在 Android 上发现，服务器 `http://localhost:8380`）：登录时先用 App 内浏览器页（Chrome 自定义标签页）打开 Nextcloud 登录页；它打不开时（例如没有支持它的浏览器、浏览器拒绝），错误被吞掉，对话框一直等待。现在：
  - App 内浏览器页打不开时，自动改用系统浏览器打开登录页（登录照样通过轮询完成）；
  - 「登录页面没有打开？点击这里」直接用系统浏览器打开；
  - 都打不开时，对话框显示原因，并提供「复制登录链接」；
  - 服务器地址不是 Nextcloud、路径不对、证书问题等导致第一步就失败时，对话框显示「无法开始 Nextcloud 登录：…」和原因，不再一直空等。
- 根本原因（是 http 地址、还是这台平板的默认浏览器不支持 App 内浏览器页）尚未在真机上确认；TC-LOGIN-03 第 6 步会记录。

## 测试
- 新增自动化测试 `nc_login_flow_test.dart`（6 项，用本地假 Nextcloud 服务器：App 内浏览器页失败 → 系统浏览器；都失败 → 报告原因；用户关闭标签页不再弹浏览器；标签页正常时不开系统浏览器；重试按钮直接用系统浏览器；非 Nextcloud 地址报错）。
- 新增真机用例 TC-LOGIN-03。

## 已知问题
- 同上一编译。

# 本次测试范围
- **必测**：TC-LOGIN-03（需要一台平板能访问的 Nextcloud；用电脑上的服务器时先 `adb reverse`）、TC-LOGIN-02。
- **同时**：之前编译交代、尚未执行的必测用例（TC-70 阅读体验、TC-URL、TC-PERSIST 等）。
- **回归**：冒烟用例。
- **不测**：KNOWN_ISSUES.md 中的不修复项。

# 提交记录

- `babef43f` test(ai): wait for the final saved state (one note with its result), not an earlier save — fixes the occasional failure
- `1d6de82d` fix(login): Nextcloud login page did not open — fall back to the system browser when the in-app tab fails, retry opens the system browser, show the reason and a copy-link button, report first-request failures; tests and TC-LOGIN-03
- `bf94c54a` docs(windows): Windows build location for the test agent (~/mnote-builds/windows/LATEST), handoff section; fetch script publishes there
- `13cb58f6` build(windows): fetch script for the GitHub Windows build; Windows test cases TC-WIN-01..05
- `2eb56bdc` build(windows): mNote Windows app — rebrand runner (mnote.exe, title, version info, icon), own installer (new AppId, no Saber file associations), min window size; GitHub workflow builds installer + portable zip
- `4ed51c90` release: notes for mnote-20261127-1238-b74fb533-debug

# 如何测试

见 `testcases/README.md`（安装、找元素、留证据、判定规则）和 `testcases/INDEX.md`（用例清单）。结果按 `testcases/RESULTS_TEMPLATE.md` 填写。
