> 隐私政策等 Saber 地址改为占位地址

# 本次改进

## 修复
- 隐私政策链接原来指向 Saber 网站，改为占位地址 `https://privacy-policy.mnote.invalid/`。`.invalid` 是保留域名，永远打不开，宁可明显失败也不显示 Saber 的隐私政策。
- 同样处理了另外两个还指向 Saber 服务的地址：注册链接，以及没有保存服务器地址时使用的「默认服务器」（原来是 Saber 作者的 Nextcloud 服务器，可能在不知情时连上去）。现在都指向 `*.mnote.invalid`，只要被用到就会连接失败。
- 删除了已不再使用的赞助链接。
- 新增自动化测试：`lib/` 里出现 Saber 服务地址、或占位地址被改成能访问的地址时测试失败。

## 已知问题
- mNote 还没有隐私政策，「隐私政策」点开是打不开的网页（有意为之）。
- App 图标仍是 Saber 的。

# 本次测试范围
- **必测**：TC-BRAND-03（新增）、TC-BRAND-01、TC-LOGIN-01
- **回归**：冒烟用例（见 testcases/INDEX.md）
- **重点关注**：任何地方都不应打开 saber.adil.hanney.org
- **不测**：Nextcloud 同步
