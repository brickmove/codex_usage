# 数据源分析

调研日期：2026-10-15。本文保留首次调研依据，当前实现与验证结果见文末。

## 调研依据

- 本机安装：`/Applications/CC Switch.app`，版本 `4.0.12`。
- 本机数据库：`~/.cc-switch/cc-switch.db`，`PRAGMA user_version = 20`。
- 数据库检查使用 SQLite URI `mode=ro` 与 `PRAGMA query_only=ON`，未修改 CC Switch 数据。
- 参考源码：`farion1231/cc-switch`，提交 `76f99d41a66e24a5ed2e8982bc494399f306bfe6`，其版本也是 `4.0.12`。版本一致不等于已确认本机安装包来自该提交；后续仍需实际对照界面验收。
- 首次调研阶段未读取 OAuth 密钥内容、未发起账户额度请求；后续已通过 Codex App Server 完成在线验证，见文末。

## 字段来源

| 需求字段 | 直接读取 CC Switch 本地数据 | 来源 / 处理 |
| --- | --- | --- |
| 周额度已用百分比 | 否 | 在线额度窗口中的使用率 |
| 周额度剩余百分比 | 否 | 对对应周窗口使用率做 `100 - usedPercent` 的展示换算 |
| 周额度自动重置时间 | 否 | 对应窗口的重置时间戳；倒计时可本地更新 |
| Credits 剩余余额 | 否 | 在线额度响应的 Credits 余额 |
| Credits 约合美元 | 否 | 复现 CC Switch 的展示折算，不能视为累计成本 |
| 剩余重置次数、各次到期时间 | 否 | 在线重置次数接口 |
| 时间范围内总成本 | 是 | 已存储的 `total_cost_usd` 求和；包含历史日汇总 |
| 时间范围内 Tokens | 是 | 按 CC Switch 的缓存语义归一后汇总 |
| 时间范围内总请求数 | 是 | 有效明细行数 + 历史日汇总的 `request_count` |
| 时间范围内缓存命中率 | 是 | 根据 CC Switch 存储的 Token 计数，复用其统计口径 |
| 查询间隔、默认时间范围 | 工具自身配置 | 建议额度默认 5 分钟，统计默认 30 秒，当天为默认范围；这些是建议值 |

“直接读取”指不需要调用外部服务，仍需根据筛选条件执行汇总。数据库没有一行可直接读取的、覆盖任意时间范围的顶部指标卡快照。

## 在线额度查询

### CC Switch 的现有实现

CC Switch 查询以下端点，并将结果放入进程内 `UsageCache`：

- `GET https://chatgpt.com/backend-api/wham/usage`：读取 `rate_limit` 的窗口使用率、窗口长度、重置时间，以及 `credits.balance`。
- `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits`：读取可用重置条目及到期时间。

请求使用 ChatGPT OAuth Bearer 凭据；有账户 ID 时附带 `ChatGPT-Account-Id`，重置次数查询还使用 `OpenAI-Beta: codex-1`。这是当前 CC Switch 使用的 ChatGPT 后端端点，不应假定为长期稳定的公开 REST API。

参考：[subscription.rs](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/services/subscription.rs)。

`UsageCache` 明确不持久化。检查到的本地代理 HTTP 路由没有暴露所需的统计或额度查询接口；`get_subscription_quota` / `get_usage_summary` 等 Tauri 命令是应用内部 IPC，独立 macOS 应用不能直接通过普通 HTTP 调用。

参考：[usage_cache.rs](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/services/usage_cache.rs)、[commands/subscription.rs](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/commands/subscription.rs)、[proxy/server.rs](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/proxy/server.rs)。

### 文档化的集成选项

Codex App Server 提供 `account/rateLimits/read`，可返回窗口、Credits 及可用重置次数；字段可能缺失。可优先验证此集成，减少直接维护后端协议和凭据刷新逻辑。该方法仍需要在线访问，依赖安装版本和登录账户支持。

CC Switch 从可用、未过期的条目计数；App Server 文档则要求以 `availableCount` 为准，不能混用两者的解析规则。

参考：[OpenAI 官方 App Server 文档](https://learn.chatgpt.com/docs/app-server#6-rate-limits-chatgpt)。

### 图一的具体含义

- “每周 已用 19%”：当前周窗口已用比例，展示剩余时为约 `81%`。
- “6d18h”：该额度窗口下一次自动重置的倒计时。
- “重置 10月30日到… / 剩余 2 次”：已存重置次数及最早到期日，不是周窗口自动重置日。
- “Credits 62,197.23 / 约 $2488”：余额与 CC Switch 的美元等值展示；该版本使用 `Credits × 0.04` 后对美元取整。这里只确认 CC Switch 的展示规则，不将其作为独立核实的官方定价承诺。

参考：[quotaRules.ts](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src/components/quota/quotaRules.ts)。

需要根据服务返回的窗口长度选择周窗口，不能固定假设一定是 primary 或 secondary。接口未返回周窗口时，应展示实际窗口或不可用状态。

## 本地统计数据

### 相关表

- `proxy_request_logs`：请求明细。名称含 proxy，但也保存 `codex_session` 等会话导入数据。
- `usage_daily_rollups`：历史按天归档，保存请求数、各类 Token、成本等。
- `session_log_sync`：CC Switch 的日志同步进度。
- `session_usage_dedup`：会话同步去重辅助数据。

本机已存在大量 `codex_session` 记录，因此读取统计不要求启用 CC Switch 代理；新记录的导入仍由 CC Switch 完成。只读工具不会触发它的会话扫描，CC Switch 停止同步时数值不会继续增长，界面应显示同步状态及数据时间。

2026-10-16 补充确认：参考提交的 `lib.rs` 在启动时同步一次，后台每 10 分钟兜底同步；用量页打开时由前端按所选间隔加扫。定时扫描受 `session_auto_sync_enabled` 控制。因此“本工具每 30 秒读取”不等于“CC Switch 每 30 秒导入”，仅启动后台应用也不能保证秒级数据。参考：[后台同步调度](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/lib.rs#L1220)。

### 成本口径

总成本只汇总 CC Switch 已写入的 `total_cost_usd`。不读取 `model_pricing` 重新定价、不重新解析 Codex 日志生成费用、不根据 Token 乘单价。

它代表 CC Switch 的统计成本，不等于订阅的实际付款金额、周额度消耗百分比或 Credits 实际扣减。不能使用该成本倒推出账户余额。

### Token 与缓存口径

令 F 为归一后的新增输入，O 为输出，W 为缓存写入，H 为缓存命中：

```text
真实消耗 Tokens = F + O + W + H
缓存命中率 = H / (F + W + H)
```

不能直接将所有 `input_tokens` 与 `cache_read_tokens` 相加：Codex 的输入通常已包含缓存部分。须按 `input_token_semantics` 解释；当前语义标记为 legacy=0、total=1、fresh=2，且兼容异常计数的回退行为。

费用使用存量金额；Token 归一与比率计算属于展示统计聚合，两者应明确区分。

参考：[usage_stats.rs](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/services/usage_stats.rs)、[sql_helpers.rs](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/services/sql_helpers.rs)。

### 筛选、归档与去重边界

1. 默认 `app_type = 'codex'`。图二选中“全部”，只有使用相同应用、供应商、模型、时间范围和同步快照才应得到相同数值。
2. 默认当天是系统本地时区的 `00:00:00` 到当前时间，不是滚动最近 24 小时；最近 7 天等预设也应与 CC Switch 对齐。
3. 代理日志与会话日志可能记录同一次调用，必须复用 CC Switch 的有效记录过滤规则，不能无条件累加。
4. 历史数据会从明细转入日汇总，不能只查明细表。只覆盖完整本地日期的范围才可纳入该日汇总；已归档数据无法恢复任意分钟粒度的边界统计。
5. 会话导入使用 `_codex_session` 作为供应商标识，现有表不保证能按真实 ChatGPT 账户拆分历史统计。实时额度是账户范围，本地统计是筛选后的本机记录范围，不应默认二者范围相同。
6. 启动时检查表和字段兼容性；以只读方式连接，使用短事务与锁等待，避免阻塞 CC Switch。不要给活跃数据库使用 `immutable=1`。

## 本机只读验证

2026-10-15 19:59:16 +08:00 读取，范围是本地当天开始到读取时刻，仅筛选 Codex：

| 指标 | 结果 |
| --- | ---: |
| 请求数 | 5,576 |
| 已存费用汇总 | $177.307633，界面可显示 $177.31 |
| 真实消耗 Tokens | 1,070,733,958，约 1.07B |
| 缓存命中率 | 97.8643%，界面可显示 97.9% |

该范围内 Codex 代理记录为 0，且历史归档不涉及当天，因此该次验证无需合并代理重复项或日归档。它验证了本地数据可读与字段口径；没有声称已对所有历史范围完成一致性验收。数值与截图拍摄时刻不同属于预期，仍需同一快照对照确认。

## 推荐实现方向

采用两个独立数据源：在线读取账户额度，只读 SQLite 读取 CC Switch 统计。额度刷新与统计刷新分别配置，默认统计当天，提供其他预设和自定义范围。展示最近成功查询时间与 CC Switch 数据同步时间，网络失败不应影响本地统计。

实现前先验证本机 Codex App Server 的字段覆盖和账户一致性；如无法覆盖，再评估兼容 CC Switch 后端查询方式。无需为统计部分建立新的计费系统，也无需默认修改 CC Switch。

## 已实施方案

2026-10-15 已完成原生 macOS 应用实现。

- 本机 `codex-cli 0.162.1` 的 `account/read` 和 `account/rateLimits/read` 调用成功，返回周窗口、Credits 及可用重置次数与到期条目；面板账户与 CC Switch 中显示的账户一致。
- 在线部分使用短生命周期的 `codex app-server` stdio 会话；完成查询后关闭子进程。未直接调用 ChatGPT 后端 REST 端点，也不另外存储登录凭据。
- 本地部分使用系统 SQLite，只读短事务查询，汇总既有金额，适配去重、缓存语义与日归档。
- 当天、最近 24 小时、7 天、30 天、全部时间已用同一统计快照对照 CC Switch 参考 SQL，四项指标全部一致；具体检查见 [验证说明](verification.md)。

## 数据扩展清单（2026-10-16）

本机 CC Switch 仍为 4.0.12，数据库版本 20。以下按只读表结构和字段覆盖检查，未读取 `providers.settings_config`、`providers.meta`、`profiles.payload` 或认证文件。这里是可扩展性调研，不表示下列所有功能已加入界面。

| 候选内容 | 数据来源 | 展示方式与优先级 | 口径和边界 |
| --- | --- | --- | --- |
| Token 构成 | `proxy_request_logs`、`usage_daily_rollups` 的输入、输出、缓存写入、缓存命中字段 | 0.4.0 已实现：独立“分析”页展示四项数值和份额，复用 `UsageSummary` | 必须复用现有缓存归一，不能把包含缓存的输入重复相加 |
| 按小时 / 按天趋势 | 明细 `created_at`，历史日汇总 `date` | 优先：今日按小时、长范围按天；切换费用 / Tokens / 请求数 | 费用汇总存量金额；明细与归档合并且保持有效记录去重；归档不能还原小时 |
| 模型分布与排行 | 两张统计表的 `model`、`request_model`、`pricing_model` | 优先：每模型费用、Tokens、请求占比，显示前 3 项后可展开 | 需要区分实际模型、请求模型与计价模型；本机今日只有一个实际模型，历史才有分布 |
| 每次请求平均费用 | 存量总费用 / 有效请求数 | 次优先：分析卡片或模型列表中的辅助列 | 这是存量金额的统计均值，不是新定价，也不是订阅实付或 Credits 扣款 |
| 会话 ID 数与排行 | 明细 `session_id`、`created_at` 及存量费用 | 次优先：活跃会话 ID 数、费用较高的会话 | 日归档不保留会话维度；子代理可能归到父线程；不能等同于用户提问数或 ChatGPT 对话数 |
| 最近请求 | 明细时间、模型、状态码、四类 Token、存量费用、来源 | 次优先：下拉面板只列最近 5～10 条，详情再展开 | 默认不展示原始错误内容、会话路径、完整请求标识或任何凭据；时间范围及来源要清晰 |
| 已记录失败数 / 状态码分布 | 明细 `status_code`，日归档 `success_count` / `request_count` | 次优先：失败条数与已记录成功率 | 本机今日全是 `codex_session` 成功行，不能据此声称真实 API 可靠性 100%；未写入的失败无法恢复 |
| 请求耗时 / 首字时间 / 输出速度 | 明细 `latency_ms`、`first_token_ms`、`output_tokens`、`data_source` | 有条件：按精确与估算样本分开展示，并附覆盖率 | 不把空值或 0 当作 0ms；日归档没有逐条首字时间和速度样本；详见下文 |
| 当前供应商与日 / 月预算 | `providers` 的安全列：名称、类型、`is_current`、预算上限 | 有条件：显示所选路由配置、预算进度 | 供应商不等同于 ChatGPT 登录账户；导入的官方会话不一定归属真实供应商，不能硬套预算；预算是用户配置而非官方额度 |
| 路由配置状态 | `proxy_config` 的启用、接管、故障切换等布尔列 | 有条件：单独“来源状态”区域 | 这是存储配置，不能直接声称运行中或健康；需要运行态校验，不展示监听地址中的敏感内容 |
| 供应商健康 / 最近探测 | `provider_health`、`stream_check_logs` | 暂不优先：有数据再启用 | 本机相关 Codex 表目前为空，不能显示绿色健康或 0ms；探测时间与真实请求时间分开 |
| 重置次数到期明细、短周期额度 | Codex App Server 在线响应 | 已有概要，可展开服务返回的重置条目及其他窗口 | 不在 CC Switch 统计库中；可用总数以接口汇总为准，详情条目可能不完整；与本机用量独立 |

### 本机字段覆盖快照

2026-10-16 08:50 的原始明细覆盖检查（不是界面去重后的业务汇总）：

- 今日 1,046 行，均为 `codex_session`；其中 1,045 行有大于 0 的 `latency_ms`，747 行有大于 0 的 `first_token_ms`；全部有会话 ID，涉及 3 个不同 ID、1 个实际模型。
- 明细历史有 10 个不同实际模型，可支持历史模型分布。`duration_ms` 在检查范围内没有有效值，不能用它生成“耗时”或“速度”。
- Codex 供应商配置 5 条，当前项 1 条，未配置有效日 / 月费用预算；健康与探测记录为 0 条。`usage_daily_rollups` 有 173 条 Codex 归档行，可支持历史日期范围。
- 数字会随 CC Switch 同步变化，仅用于判断数据覆盖；不作为应用默认值。

### 耗时和速度为什么需要单独处理

CC Switch 的 Codex 会话导入会根据事件时间戳估计耗时与首字，不能把这些列直接标为精确网络计时。[会话计时实现](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/services/session_usage_codex.rs#L276)。

参考版本把代理精确样本和会话估算样本分开：前者速度用符合条件的输出总量除以生成总时间，后者含首字等待并使用不同样本门槛；首字以中位数展示，估算值带 `≈`。后续实现应复用这一规则，不能直接平均每条 tok/s，也不能把两类样本混合。[统计与样本规则](https://github.com/farion1231/cc-switch/blob/76f99d41a66e24a5ed2e8982bc494399f306bfe6/src-tauri/src/services/usage_stats.rs#L119)。

0.4.0 已展示 Token 构成，份额分母为全部 Token（含输出）；概览的缓存命中率仍以全部输入为分母。趋势、模型排行与后续请求/会话维度尚未实现；耗时和速度在明确样本类型及覆盖率后加入。菜单栏继续只承担用户选择的少数图标与数值，分析内容放在下拉面板中。

### 当前账户的边界

当前账户来自 `account/read`，只取 `type`、`email`、`planType`；本应用不发起登录，不读取或保存 OAuth 密钥。账户识别先于额度请求返回，因此额度接口暂不可用时仍可显示已识别账户。未经重新确认时显示“上次识别账户”；切换 Codex 配置后清除旧身份。API Key 模式显示认证方式而非虚构邮箱。[OpenAI 官方账户协议](https://learn.chatgpt.com/docs/app-server#auth-endpoints)。

本机历史统计仍是 Codex 记录范围，不能因顶部展示当前账户就将全部本机费用归到该账户。
