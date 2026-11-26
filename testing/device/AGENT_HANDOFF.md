# mNote 测试交接（给测试 Agent）

所有编译都在服务器 **h3c-4s-03** 上，目录 **`/home/johnson/mnote-builds/`**：

```
/home/johnson/mnote-builds/
  README.md                 本文件
  LATEST -> <编译编号>/      指向最新一次编译
  BUILDS.md                 全部编译列表（编号、时间、commit、一句话说明）
  <编译编号>/                每次编译一个目录，例如 mnote-20261126-1307-14bfa192-debug/
    <编译编号>.apk           要测的安装包
    RELEASE_NOTES.md        本次改了什么、**本次测试范围**（必读，决定跑哪些用例）
    manifest.json           包名、版本、commit、APK SHA-256（安装前核对）
    testcases/
      README.md             安装、找界面元素、留证据、判定规则
      INDEX.md              用例清单（优先级、冒烟标记）
      cases/TC-*.md         用例
      assets/               测试素材（论文 PDF）
      reference/            参考截图
      RESULTS_TEMPLATE.md   结果报告模板
    results/                **测试结果放这里**（见下）
```

## 每次测试怎么做
1. `cat /home/johnson/mnote-builds/LATEST/RELEASE_NOTES.md`，看「本次测试范围」。
2. 按 `LATEST/testcases/README.md` 安装和执行用例。adb 在服务器上的路径是 `/home/johnson/Android/Sdk/platform-tools/adb`（设备接在哪台机器上就用哪台的 adb）。
3. 结果写到 **`/home/johnson/mnote-builds/<编译编号>/results/`**：
   - `RESULTS.md`：按 `testcases/RESULTS_TEMPLATE.md` 填写
   - 截图、日志等证据文件也放在这个目录（文件名以用例 ID 开头，如 `TC-EXC-01_3.png`、`TC-EXC-01_logcat.txt`）
   - 同一个编译测了多轮时，用子目录 `results/run-2/`、`results/run-3/`
4. 只改 `results/` 里的东西；编译目录里其他文件不要改（它们是这次编译的快照）。

## 其他
- 编译编号格式：`mnote-<日期>-<北京时间>-<commit 前 8 位>-<debug|release>`。
- 包名 `io.github.cnwuzhh.mnote`。旧测试包 `com.adilhanney.saber` 是另一个 App，测试前卸掉。
- 用例写得不清楚或与界面对不上，记在 `RESULTS.md` 的「用例本身的问题」里，不要自行修改用例。
- 源代码和用例源文件在同一台服务器的 `/home/johnson/mNote`（git 仓库），一般不需要看。
