# 项目协作规则

- 默认使用简体中文解释、记录检查结果和撰写提交说明。
- 日常修复提交、推送到 `main`，不因单个问题递增发布版本、创建版本标签或发布 Release。未发布改动记录在 `CHANGELOG.md`。
- 两次公开 Release 至少间隔一个自然月，以最近一次 `published_at` 加一个月为准；月末按下月最后一天处理，保留 UTC 时分秒。草稿不计，预发布也计入间隔。
- 发布前必须通过 `scripts/release-policy.py` 与工作流中的发布间隔检查。未满足间隔时只提交代码和本地构建，不创建 Release；不得通过改发布日期、移动标签或覆盖既有附件绕过规则。
- 本地验证可递增 `CFBundleVersion`，`CFBundleShortVersionString` 与版本标签在统一发版时再调整。既有公开安装包与历史版本标签保持不变。
- 临时应用、QA 应用和解包目录放在 `.noindex` 目录中；验证结束退出并注销副本，正式安装位置为 `/Applications/Codex Usage.app`。

完整发布规则见 [开发指南](docs/development.md#发布流程)。
