# 持久化与恢复

前置：TC-SET-01、TC-SET-02 完成，文档里至少有 2 张卡片和几笔手写（不够时先摘录、在「手写」模式写几笔）。横屏。
`PKG=io.github.cnwuzhh.mnote`。debug 包可用 `adb shell run-as $PKG ...` 查看数据目录 `files/mnote/`。

**什么时候保存**（判定用）：
- 卡片的新增、删除、移动、改颜色：立即保存。
- 改标题、批注等文字编辑：停止输入约 0.4 秒后保存。
- 阅读位置（页码）：停止翻页约 1 秒后保存。
- 手写笔迹：停笔约 0.6 秒后保存。
- 切到后台（按 Home、切换 App、锁屏）时：以上所有未保存的改动立即写入。

## TC-PERSIST-02 切到后台后被杀，数据不丢　P0
| # | 操作 | 期望 |
|---|---|---|
| 1 | 在「手写」模式写一笔，**立刻**按 Home 键（`adb shell input keyevent KEYCODE_HOME`），然后马上 `adb shell am force-stop $PKG` | — |
| 2 | 重新打开文档 | 刚才那一笔还在 |
| 3 | 改一张卡片的批注，输入后立刻按 Home 并 force-stop；重新打开 | 批注是改后的内容 |
| 4 | 翻到第 5 页，立刻按 Home 并 force-stop；重新打开文档 | 回到第 5 页 |

## TC-PERSIST-03 不经后台直接被杀（记录型）　P2
模拟 App 崩溃或被系统直接结束（不经过后台）。这时只有已经过了上面「保存时机」的改动能保证保存。
| # | 操作 | 期望 |
|---|---|---|
| 1 | 摘录一张卡片，「已加入」提示出现后**立刻** force-stop（不按 Home）；重新打开 | 卡片在（新增卡片是立即保存的） |
| 2 | 写一笔后不到 0.5 秒就 force-stop；重新打开 | **记录**这一笔是否还在（可能丢失最后一笔，不算失败）；之前写的笔迹都在 |
| 3 | 日志 | 无 Flutter 异常 |

## TC-PERSIST-04 删除的学习集不会回来　P0
| # | 操作 | 期望 |
|---|---|---|
| 1 | 新建学习集「临时」，导入论文，摘录一张卡片后返回；在学习集页删除「临时」 | 列表里消失 |
| 2 | 立刻 force-stop 并重新启动 | 「临时」**没有**重新出现 |
| 3 | `adb shell run-as $PKG ls files/mnote/sets` | 没有「临时」对应的目录（与其他学习集目录数比较） |

## TC-PERSIST-05 损坏的笔迹文件被保留并提示　P1
仅 debug 包（需要 run-as）。
| # | 操作 | 期望 |
|---|---|---|
| 1 | 找到笔迹文件：`adb shell run-as $PKG sh -c 'ls files/mnote/sets/*/ink/'`，记下一个 `*.ink.bson` | — |
| 2 | 写入垃圾数据：`adb shell run-as $PKG sh -c 'echo broken > files/mnote/sets/<学习集目录>/ink/<文件名>'` | — |
| 3 | 打开对应文档 | 提示「这份文档的笔迹文件已损坏：已另存备份，笔迹从空白开始」；App 不崩溃；摘录卡片、高亮都正常 |
| 4 | `adb shell run-as $PKG sh -c 'ls files/mnote/sets/<学习集目录>/ink/'` | 有一个 `<文件名>.corrupt-<数字>` 备份文件 |
| 5 | 写一笔，重启后打开 | 新写的一笔在 |

## TC-PERSIST-06 损坏的学习集文件不影响其他学习集　P1
仅 debug 包。需要至少两个学习集。
| # | 操作 | 期望 |
|---|---|---|
| 1 | 选一个**不重要的**学习集目录 X：`adb shell run-as $PKG sh -c 'ls files/mnote/sets/'` | — |
| 2 | 把它的 set.json 截断：`adb shell run-as $PKG sh -c 'head -c 50 files/mnote/sets/X/set.json > /data/local/tmp/x; cat /data/local/tmp/x > files/mnote/sets/X/set.json'`（run-as 无法写 /data/local/tmp 时，改用 `echo '{"id":' > files/mnote/sets/X/set.json`） | — |
| 3 | force-stop 后重新启动 | 其他学习集都在、内容完整；损坏的 X 不显示；App 不崩溃 |
| 4 | `adb shell run-as $PKG sh -c 'ls files/mnote/sets/X/'` | set.json 仍在（未被删除或覆盖，留给恢复） |
