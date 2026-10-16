# 0.4.0 技术方案

原生 SwiftPM 无第三方依赖。沿用 UsageCore 查询/RPC/缓存；本轮不改 SQL、凭据或新闻接口。根规则以用户会话为准，原项目 .specify 章程/模板/脚本不存在，按已归档 SKILL.md 和 commands 的流程手工适配原生项目，未声称执行缺失脚本。

## 决策与接口

1. 可信表现使用纯数据展示对象：单一窗口状态决定剩余、已用、条宽、AX；账户 stale 屏蔽 Credits/估值/重置及到期。窗口本身 resetDate 过期可局部失效。保留最后查询时间。
2. Token 构成从 UsageSummary 四字段读取；无新的存储结构或数据库查询。份额 = 该分量 / realTotalTokens，0 时不计算。读取错误不将旧构成冒充当前值；延迟非零保留同一来源提示。
3. AppModel 增加 analysis 页状态与统一 panelHeight；AppDelegate 在打开时取 status button 所在 screen.visibleFrame，模型计算同一高度供 SwiftUI / NSPopover。范围切换不再改变外层高度。
4. SettingsView 保持单一 draft，分类只控制可见内容，不重建草稿。日期验证覆盖面板和设置，允许相同时间；未应用的输入不覆盖原查询范围。
5. 来源状态直接使用 StatisticsSyncState；时间细节不是独立新鲜度判定。原有 NSWorkspace / NWPathMonitor / UUID 竞态保护不改。
6. 发布：保留 v0.3.3 → feb80a2；自动化从指定标签独立 worktree 测试/打包/校验，先 draft，附件完整后公开；全仓串行发布，不覆盖已公开版本。0.4.0 更新 plist 和版本说明。

## 研究与替代方案

新增模型聚合/小时趋势需要复制去重口径、处理日归档精度，暂不实现；四类 Token 无这些风险。未验证 SQL 取消性能问题保留为研究假设，不按缺陷修改。已知平台限制：arm64 本机与 CI；macOS 14 部署目标不等于旧系统实测；ad-hoc 无公证。

## 审查后修订

根据 des-review.md：四类份额不复用 cacheHitRate；来源异常/归档提示不折叠；次级窗口单独失效；未应用自定义范围明确展示已查询区间；所有页面用同一限高值；设置跨分类错误在页尾可见。无新增待澄清关键接口。
