# 用例清单

优先级：P0 必须通过才能发给用户；P1 重要；P2 次要。`冒烟` = 每次编译都要跑。

| ID | 名称 | 优先级 | 冒烟 | 文件 | 覆盖 |
|---|---|---|---|---|---|
| TC-INST-01 | 安装并启动 | P0 | ✓ | cases/TC-10-install-brand-login.md | 包名、App 名、启动页 |
| TC-BRAND-01 | 界面里没有 Saber 字样 | P0 | ✓ | cases/TC-10-install-brand-login.md | 去 Saber 品牌 |
| TC-BRAND-02 | 不弹崩溃报告授权 | P0 | ✓ | cases/TC-10-install-brand-login.md | 关闭上游崩溃报告 |
| TC-BRAND-03 | 隐私政策等链接是占位地址 | P1 |  | cases/TC-10-install-brand-login.md | 不指向 Saber 服务 |
| TC-HOME-01 | 首页没有欢迎页 | P1 |  | cases/TC-10-install-brand-login.md | 删除欢迎页 |
| TC-LOGIN-01 | 只能登录自己的 Nextcloud | P1 |  | cases/TC-10-install-brand-login.md | 去掉 Saber 服务器；地址校验修复 |
| TC-LOGIN-02 | 横屏弹出键盘不溢出 | P1 |  | cases/TC-10-install-brand-login.md | 键盘溢出修复 |
| TC-DATA-01 | 数据文件夹叫 mNote | P2 |  | cases/TC-10-install-brand-login.md | 数据目录改名 |
| TC-SET-01 | 新建学习集 | P0 | ✓ | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 1 |
| TC-SET-02 | 导入 PDF | P0 | ✓ | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 2 |
| TC-READ-01 | 三栏工作区 | P0 | ✓ | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 3 |
| TC-EXC-01 | 摘录为卡片（黄） | P0 | ✓ | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 4–5 |
| TC-EXC-02 | 改卡片标题 | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 6 |
| TC-EXC-03 | 目录跳转 | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 7 |
| TC-EXC-04 | 第 2 页证据句（蓝） | P0 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 8 |
| TC-EXC-05 | 框选图片 | P0 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 9 |
| TC-EXC-06 | 第 3 页易错句（红） | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 10 |
| TC-EXC-07 | 仅高亮、复制 | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 A1 |
| TC-MAP-01 | 拖动改层级 | P0 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 11 |
| TC-MAP-02 | 回到原文 | P0 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 14 |
| TC-MAP-03 | 收起 / 展开 / 调宽脑图 | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 A5 |
| TC-NAV-01 | 全文搜索 | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 12 |
| TC-NAV-02 | 第 13 页摘录（绿） | P2 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 13 |
| TC-CARD-01 | 卡片详情编辑与删除 | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 15、A4 |
| TC-PERSIST-01 | 重启后数据保留 | P0 | ✓ | cases/TC-20-studyset-reader-excerpt.md | UC-01 步骤 16 |
| TC-UI-01 | 夜读 | P1 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 A8 |
| TC-UI-02 | 竖屏 | P2 |  | cases/TC-20-studyset-reader-excerpt.md | UC-01 A6（部分） |
| TC-UI-03 | 未开放的模式 | P2 |  | cases/TC-20-studyset-reader-excerpt.md | 四模式工具条 |
| TC-INK-01 | 进入手写模式 | P0 | ✓ | cases/TC-30-ink-export.md | UC-02 步骤 1 |
| TC-INK-02 | 笔写、手指滚动 | P0 | ✓ | cases/TC-30-ink-export.md | UC-02 步骤 2–3 |
| TC-INK-03 | 缩放后笔迹位置不变 | P0 |  | cases/TC-30-ink-export.md | UC-02 步骤 4 |
| TC-INK-04 | 荧光笔不盖住文字 | P1 |  | cases/TC-30-ink-export.md | UC-02 步骤 5、B4 |
| TC-INK-05 | 撤销 / 重做 | P0 |  | cases/TC-30-ink-export.md | UC-02 步骤 6 |
| TC-INK-06 | 橡皮 | P0 |  | cases/TC-30-ink-export.md | UC-02 步骤 7 |
| TC-INK-07 | 套索摘录为卡片 | P0 |  | cases/TC-30-ink-export.md | UC-02 步骤 8–9、B5 |
| TC-INK-08 | 手指书写开关 | P1 |  | cases/TC-30-ink-export.md | UC-02 B1 |
| TC-INK-09 | 跨页的一笔 | P2 |  | cases/TC-30-ink-export.md | UC-02 B2 |
| TC-INK-10 | 手写模式下其他操作照常 | P1 |  | cases/TC-30-ink-export.md | UC-02 B3、B7 |
| TC-INK-11 | 笔迹持久化 | P0 | ✓ | cases/TC-30-ink-export.md | UC-02 步骤 10 |
| TC-INK-12 | 很多笔时的流畅度 | P2 |  | cases/TC-30-ink-export.md | UC-02 B6 |
| TC-EXP-01 | 导出带批注的 PDF | P0 |  | cases/TC-30-ink-export.md | UC-02 步骤 11 |

冒烟顺序：TC-INST-01 → TC-BRAND-01 → TC-BRAND-02 → TC-SET-01 → TC-SET-02 → TC-READ-01 → TC-EXC-01 → TC-INK-01 → TC-INK-02 → TC-INK-11 → TC-PERSIST-01。

## 维护规则
- 用例 ID 一经发布不改、不复用；功能删除时把用例标为「已废弃」并保留。
- 每次改功能时同步改对应用例，并在 `docs/releases/UNRELEASED.md` 的「本次测试范围」里列出。
