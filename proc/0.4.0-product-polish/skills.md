# 技能应用记录

枚举基线：43 个 SKILL.md；本轮选用 28 项，不适用/重复 15 项。已执行项有下列实际产出，两个正式版本的公开附件均已下载核验，结果见 summary.md。

来源：`/Users/yuxiang/mygit/skills/<名称>/SKILL.md`，优先采用用户指定技能库。归档 commands 为详细后备说明。

## 路由与适配

执行级别 Full；独立 UI/AX、Runtime/Data/Security 门控；无受监管行业业务门控。唯一主链 req-story → req-analysis/clarify → des-design/solution/review → dev-plan → dev-implement。
证据：跨 SwiftUI/AppKit 界面、可信状态、SQLite 统计解释和分发；基线 93 项测试，两轮独立审查。允许修改 Sources/Tests/Resources/scripts/.github/README/docs/proc/design；本机只读数据诊断，设置验证使用隔离示例，保留现有生产偏好。
非目标：定价、重导入会话、登录/凭据、修改 CC Switch、小时趋势或模型排名、系统睡眠、权限扩大。验收：R1–R9、已确认阻断项清零、28 项适用技能逐项留下实际结果；15 项明确不适用，不以机械跑命令冒充应用。
原项目 .agents helper、.specify 模板/章程/调度脚本缺失；手工原生适配并记录限制，不宣称执行缺失脚本或通过其校验。Electron、npm、tsc、行业规范均不适用。用户已授权全部适用打磨、提交推送与发布，不重复索取已有授权。
派发 delegate：产品审查和运行数据审查为 parallel-read（depends_on=基线，allowed_paths=源码/文档只读，max_parallel=2）；计划只读依赖规格/方案；实现 serial-write 单一写入者；独立最终审查依赖实现版本。实际协作工具回执已收到，reviewer 不实现被审查范围。模型按会话继承，未冒称归档中不可用的 terra 或自动切换 astra；主代理保留最终判断。

## 逐项清单

| 技能 | 状态 | 实际产出 / 适用理由 |
| --- | --- | --- |
| bug-list | 不适用 | 需要既定 Excel 缺陷表/模板输入，本项目没有；不凭空创建缺陷台账。 |
| bug-task | 不适用 | 依赖缺陷表和 bug 任务源；本轮用正式需求/方案/任务链。 |
| check | 已执行 | SwiftPM 106 项、shell/plist、Workflow YAML/run 语法、包校验、本地 Markdown 链接 |
| code-audit | 已执行 | des-review.md 首轮缺陷与最终复审；确认 P0/P1/P2 未关闭项为 0 |
| code-review | 已执行 | 两位独立审查者复核源码/测试/资源指纹 ef6662c…，确认阻断项为 0 |
| codex-workflow | 不适用 | 用于旧 Claude 工作流迁移，本次消费外部技能而非迁移其整套治理设施。 |
| commit-split | 已执行 | 按授权分组：发布基础设施 12c0aa3、产品实现 7d98837 已推送；交付记录 3f00276 已推送；公开发布证据另作本次补录 |
| constitution | 不适用 | 没有修改项目章程的目标；本次遵循用户约束，不附带建立跨项目治理。 |
| context-pack | 已执行 | 最小上下文：会话规则、README、Package.swift、Sources/Tests、数据源文档 |
| des-design | 已执行 | ../../design/0.4.0-product-polish/framework.md 与两个 page 文件 |
| des-guide | 已执行 | ../../design/0.4.0-product-polish/Guidelines.md |
| des-review | 已执行 | des-review.md |
| des-solution | 已执行 | tech-solution.md |
| des-update | 已执行 | tech-solution.md 审查后修订 |
| dev-debug | 不适用 | 没有尚未定位的运行故障；审查已确认展示逻辑，不捏造调试任务。 |
| dev-fix | 不适用 | 与已选 dev-implement 主链重复，不启动第二条修复写入流程。 |
| dev-implement | 已执行 | T2–T4 实施完成；先红后绿、106 项测试、14 张原生预览和实际 QA 交互 |
| dev-plan | 已执行 | tasks/plan.md、tasks/plan-summary.md；独立 plan_tasks 代理提案并由主代理复核 |
| dev-planfix | 不适用 | 与正式需求→方案→计划主链重复；保持一个主流程。 |
| diff-review | 不适用 | 技能明确仅 JS/TS/Vue 文件，本项目 Swift 无匹配；使用 code-review。 |
| doc-sync | 已执行 | README / 数据源 / 验证 / 发布文档与当前代码同步；旧新闻入口用量同步为概览 |
| issue | 不适用 | 没有会议纪要/外部议题发布请求，不发布 issue 或消息。 |
| item-discuss | 不适用 | 没有 item 工作项需要补会话；本轮 multi-discuss 已覆盖两轮技术/产品讨论。 |
| learn | 已执行 | docs/tech/可信数据在文字图形与辅助功能中的一致呈现.md 及 README 索引已保存 |
| multi-discuss | 已执行 | des-review.md：两轮独立产品/数据反向审查 |
| precommit-review | 已执行 | 确认问题→方案→修正→独立复审→106 项回归闭环；AX 日期追加问题已关闭 |
| rag-analysis | 不适用 | 无独立待分析知识库输入，现有源码分析使用 code-audit。 |
| rag-index | 不适用 | 无 RAG 知识库/索引，不制造空索引。 |
| rag-search | 不适用 | 无待检索本地 RAG 资源，直接读取项目源码和文档。 |
| rag-split | 不适用 | 文档规模不需要知识库分片，拆分会增加维护成本。 |
| rag-summary | 不适用 | 本轮已有明确需求/技术文档，不额外生成重复 RAG 摘要。 |
| req-analysis | 已执行 | req-specification.md |
| req-boundary | 已执行 | ../../docs/problem/item-task-20261016/req-boundary/product-polish.md |
| req-case | 已执行 | test-case.md |
| req-clarify | 已执行 | req-specification.md 的澄清与覆盖扫描 |
| req-story | 已执行 | req-story.md |
| req-update | 已执行 | req-specification.md 变更：设计反馈回填 |
| spec-lint | 已执行 | 24 份 Markdown 本地链接、R1–R9 任务映射与需求/设计一致性通过；无 RAG 产物需刷新 |
| verification-selector | 已执行 | verification-plan.md：只选择检查，不冒称已运行 |
| vibe | 已执行 | Full 路由与实际派发；本文件及 des-review.md |
| web-search | 已执行 | GitHub Actions 官方文档及 Apple HIG，research.md；仅事实有来源，设计为项目判断 |
| workflow-result | 已执行 | selector-result.json：保留 raw 与缺失 helper 警告 |
| workflow-selectors | 已执行 | context / domain / verification 联合选择，原生手工适配 |

## 最终门控

源码/测试/资源最终指纹：`ef6662c61006603030e39acebdc480858309d7d742d4eb3d19291fdf169a3491`；实际 reviewer：`/root/product_audit` 与 `/root/runtime_audit`，均独立复算并只读审查，非实现者。实现任务的测试文件由 `/root/plan_tasks` 串行有界写入后交回主代理；其后主代理才恢复源码写入。原归档的派发校验脚本不存在，采用实际工具回执和指纹，不把 planning 校验冒充 agent 执行。

28 项适用技能的实际执行已覆盖；15 项不适用仍保留，不改成“通过”。本轮 UI/UX/UE 评级 B（原生手工适配），Runtime/Data/Security 以对应测试、只读不变和独立审查为证据；硬件睡眠、VoiceOver 连续朗读、多屏切换、旧系统/Intel/公证保留未实测边界。公开发布的最终下载核验通过，见 summary.md。
