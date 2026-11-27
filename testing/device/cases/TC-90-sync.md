# Nextcloud 同步学习集

前置：一台平板能访问的 Nextcloud（电脑上的服务器先 `adb reverse tcp:8380 tcp:8380`，地址 `http://localhost:8380`），一个测试账号；按 TC-LOGIN-03 登录，并设置加密密码（记下来，恢复时要用）。`PKG=io.github.cnwuzhh.mnote`。
**说明**：学习集保存在 Saber 数据目录下的隐藏文件夹 `.mnote/`（debug 包：`adb shell run-as $PKG ls app_flutter/mNote/.mnote/sets`），由 Saber 的同步上传到 Nextcloud 的 `/mNote/`。远端文件名和内容都是加密的（`*.sbe`），看不出是哪个文件，只能数数量、看大小。
**冲突限制（不算失败）**：同一个学习集在两台设备上同时修改时，以后保存的那一份为准，另一份的修改会丢失。

## TC-NC-03 学习集上传到 Nextcloud　P0
| # | 操作 | 期望 |
|---|---|---|
| 1 | 升级到本编译后打开 App（旧版本里已有学习集时） | 原有学习集都在（自动从旧位置迁移到 `.mnote/`）；`run-as $PKG ls files/mnote` 不存在或为空 |
| 2 | 在 Nextcloud 网页里记下 `/mNote/` 的文件数 | — |
| 3 | 新建学习集「同步测试」，导入论文，摘录 2 张卡片，手写一笔，翻译一句 | — |
| 4 | 等 1 分钟（或在首页下拉刷新触发同步） | `/mNote/` 文件数增加（至少：set.json、PDF、笔迹各一个 `.sbe`）；有一个大小约等于 PDF（约 1.5 MB）的 `.sbe` |
| 5 | `adb logcat -d | grep -E "SyncerUploader|SaberSyncInterface"` | 有 `Transfer complete … .mnote/sets/…` 之类的上传记录；**没有** `Unhandled Exception` |

## TC-NC-04 远端目录已存在时不报错　P0
| # | 操作 | 期望 |
|---|---|---|
| 1 | 在 Nextcloud 网页里删除 `/mNote/` 整个文件夹 | — |
| 2 | 在 App 里退出登录再登录（同一账号），等待同步 | Nextcloud 上重新出现 `/mNote/` 和 `config.sbc`；`adb logcat -d | grep -E "405|MethodNotAllowed|Unhandled"` **没有**未处理的 405（可以有一行 `app directory was created concurrently`） |
| 3 | 再次刷新同步 | 正常，无异常 |

## TC-NC-05 换设备 / 重装后恢复学习集　P0
| # | 操作 | 期望 |
|---|---|---|
| 1 | 完成 TC-NC-03 后：`adb shell pm clear $PKG`（清空 App 数据，相当于换了一台设备） | App 回到初始状态，学习集列表为空 |
| 2 | 登录同一个 Nextcloud 账号，输入同一个加密密码，等待同步（首页下拉刷新） | 学习集页出现「同步测试」（可能需要几十秒；PDF 较大） |
| 3 | 打开它 | 文档能打开，2 张卡片和高亮都在，手写笔迹在，「译」标记在 |
| 4 | 记录从登录到学习集出现、到 PDF 能打开分别用了多久 | — |

## TC-NC-06 删除学习集也从 Nextcloud 删除　P1
| # | 操作 | 期望 |
|---|---|---|
| 1 | 删除「同步测试」，等待同步 | Nextcloud `/mNote/` 里对应的文件变成 0 字节（Saber 用 0 字节文件表示已删除）或消失 |
| 2 | 再做一次 TC-NC-05 的第 1、2 步 | 「同步测试」**不会**回来 |

## TC-NC-07 Saber 笔记列表不出现隐藏目录　P2
| # | 操作 | 期望 |
|---|---|---|
| 1 | 打开 Saber 原有的「全部笔记 / 浏览」页 | 看不到 `.mnote` 文件夹 |
