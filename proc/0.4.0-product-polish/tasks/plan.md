# 0.4.0 开发计划

由独立 plan_tasks 代理根据规格/方案提出，主代理复核采纳。原生适配；单一串行写入者，独立只读审查可并行。T1 发布与产品阅读/设计可并行，其余源文件实施串行。

- [x] T1 / R9：保留并发布基线。范围 .github/workflows/release.yml、docs/releases/v0.3.3.md；无依赖。v0.3.3 源码标签保持 feb80a2，独立构建并公开双附件；已真实下载验证 SHA-256 / 版本 / arm64 / codesign。
- [x] T2 / R1,R3,R4,R8：可信展示策略。范围 Sources/UsageCore 的新展示策略、Tests/UsageCoreTests 的针对性测试；依赖正式需求/方案。先写失效/局部过期、Token 分母/零值、日期/限高回归，再实现；保留 SQL/RPC/MenuDisplay 行为。验收：所有值与 AX 统一失效，四分量来自同一 summary，历史 current 正常。
- [x] T3 / R2,R3,R4,R6,R7,R8：三页面板。范围 AppModel / PopoverView / AppDelegate / EntryPoint 和必要的新视图；依赖 T2。概览/分析/重置动态、常规元数据折叠、异常常显、日期草稿分离、同一屏幕限高。验收：测试与原生深浅/错误/未同步/小尺寸/AX。
- [x] T4 / R1,R5,R6：分类设置。范围 SettingsView 与必要的原生预览入口；依赖 T2,T3。菜单栏/数据与刷新/重置动态共享一个草稿，取消不保存，底部可见错误原因。验收：排序/默认/仅图标保持，跨页草稿与保存/取消验证。
- [x] T5 / R1–R9：独立验收和交付。范围 plist / README / docs / proc / design；依赖 T1,T3,T4。全测试、原生验证、包校验、独立最终源码审查、文档与技能结果复核；零确认阻断问题后按组提交推送，0.4.0 独立标签和 Release。

不创建真实数据库或凭据，不写入源 CC Switch；不在未验证情况下增加趋势/模型排行或 SQL 取消机制。每阶段证据回填 summary.md，实际测试日志/截图留 build/，不提交生成物。
