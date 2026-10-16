# Codex Usage

面向 macOS 的 Codex 菜单栏用量显示工具。

原生 SwiftUI / AppKit 应用，常驻菜单栏，支持深浅色外观。额度通过 Codex App Server 查询，统计直接读取 CC Switch 已存数据。

## 下载

从 [GitHub Releases](https://github.com/brickmove/codex_usage/releases) 下载安装包与 SHA-256 校验文件。打磨前的初始基线固定为 [v0.3.3](https://github.com/brickmove/codex_usage/releases/tag/v0.3.3)，产品打磨版本为 **0.4.0**。当前提供 Apple Silicon 安装包，macOS 14+；签名与公证限制见文末。

## 功能范围

- 菜单栏及弹出面板显示 Codex 剩余周额度、Credits 余额、自动重置时间和可用重置次数。
- 支持设置自动查询间隔及手动刷新。
- 独立显示当前 Codex 账户邮箱和套餐，直接使用已有登录状态；额度查询失败不隐藏已识别账户。
- 独立“重置动态”标签页集成 AIHOT 的 Tibo 重置公告，并提供可关闭的菜单栏新动态提示。
- 从 CC Switch 现有统计数据读取成本，不根据模型价格重新计算。
- 显示指定时间范围的真实消耗 Tokens、请求数和缓存命中率；默认使用系统本地时区的当天，可切换范围。
- 独立“分析”页展示新增输入、输出、缓存写入、缓存命中四类 Token 的数值与份额，直接复用同一统计结果。

## 已确认的数据来源

统计数据可只读查询 `~/.cc-switch/cc-switch.db`；实时订阅额度需要在线查询。CC Switch 的额度缓存没有持久化，不能直接从此数据库取得。

字段映射、接口选项、统计口径与本机验证结果见 [数据源分析](docs/data-sources.md)。

## 构建与运行

需要 macOS 14 或更高版本、Xcode 命令行工具 / Swift 5.9 或更高版本，以及已安装并登录的 Codex CLI。没有第三方 Swift 包依赖。

安装到本机“应用程序”：

```bash
./scripts/install-app.sh
```

安装后可在 Finder 的“应用程序”中找到 **Codex Usage**，双击即可启动。更新前先从菜单栏退出应用，再重新安装；已有设置会保留。

生成可双击安装的标准 macOS 安装包：

```bash
./scripts/package-app.sh
```

安装包位于 `dist/Codex-Usage-<版本>-<架构>.pkg`，同目录附带 SHA-256 校验文件。双击安装包并按系统安装器提示操作，应用会安装到 `/Applications/Codex Usage.app`。安装包仅包含应用本身，不包含个人统计库、登录凭据或设置。接收安装包的机器无需 Swift 开发工具，仍需 Codex CLI 及 CC Switch 提供相应数据。

仅构建、运行开发版本：

```bash
./scripts/build-app.sh
open "build/Codex Usage.app"
```

生成的应用位于 `build/Codex Usage.app`，也可双击启动或复制到“应用程序”。默认只驻留菜单栏，首次启动会展开面板；设置窗口打开时临时显示 Dock 图标。右击菜单栏状态项可进入设置或退出。

菜单栏使用原生 SF Symbols 图标搭配数值，例如仪表图标配 `80%`、余额图标配 `62.2K`、时钟图标配 `6d17h`，不显示冗长标签。悬停可查看完整指标名称、统计范围和重置说明，下拉面板提供详情。在“设置 → 菜单栏”中可自由勾选显示项、使用上下箭头调整顺序，并查看与实际菜单栏使用相同渲染方式的预览；保存后生效，下次启动恢复。也可选择“仅显示图标”。

可选项目包括：剩余额度、已用额度、Credits 余额、自动重置倒计时、自动重置时间、可用重置次数，以及统计费用、Token 用量、请求数和缓存命中率。各项使用不同图标；统计范围显示在悬停说明中，例如“今日费用 $12.34”“近7天费用 $12.34”或“所选时段费用 $12.34”。每周额度按接口返回的额度周期展示，与统计范围独立。旧版隐藏 Credits 或倒计时的偏好会自动保留。

## 设置与统计范围

设置按“菜单栏”“数据与刷新”“重置动态”分类。所有分类共享一份草稿，切页不会丢失编辑；取消或关窗不保存，点击“保存并刷新”才生效。日期倒置会就地解释并禁用保存，其他分类也会显示错误原因。

- 额度默认每 5 分钟刷新，统计默认每 30 秒读取；可分别调整或设为手动刷新。
- 可开启“自动在后台启动 CC Switch”，在来源未运行时启动它，继续复用它的会话同步与费用结果。旧版设置迁移后默认关闭，按需要开启；本工具退出时不会退出 CC Switch。
- 启动时刷新；系统唤醒、屏幕恢复及解锁后自动恢复读取。若网络尚未就绪，按 2、5、10、20、30、60 秒间隔重试（每次请求自身仍有超时）；网络恢复时可提前重试。恢复过程不依赖定时刷新开关，倒计时由本地更新。
- 时间范围默认当天，支持最近 24 小时、最近 7 天、最近 30 天、全部时间和自定义起止时间。自定义后点击“应用范围”；未应用的日期草稿不改变已查询数据。开始时间晚于结束时间时会就地提示并禁用应用，相同起止时间仍有效。
- 当天按系统本地时区的午夜开始计算。范围选择和其他设置保存在本机，下次启动恢复。
- 数据库默认 `~/.cc-switch/cc-switch.db`；Codex CLI 自动查找，也可指定可执行文件和配置目录。
- 额度跟随所选 Codex 配置的登录账户；本地统计固定筛选 Codex，会话历史不保证能按 ChatGPT 账户拆分。
- `⌘R` 刷新、`⌘,` 打开设置、`Esc` 关闭面板、`⌘Q` 退出。

工具不保存 OAuth 凭据，凭据读取与刷新由 Codex 自身管理。设置只保存路径、时间范围及显示偏好。

账户邮箱在面板顶部显示，支持选择复制；套餐显示在同一区域。尚未重新确认时标为“上次识别账户”，本地身份核对成功后标为“当前账户”。退出登录会清除旧身份；API Key 登录显示认证方式。账户显示信息只在内存中保留。

## 数据状态

额度查询失败时显示错误及重试入口，菜单栏不继续显示旧的可用比例。网络失败不影响本地统计。超过额度快照有效时间或自动重置时刻会标记待更新；面板中的数字、进度条、Credits 估值、重置次数与辅助功能文本统一失效，不继续暴露旧额度。

统计显示 CC Switch 会话同步时间、最近请求时间及本次读取时间。CC Switch 未运行或来源较长时间未更新时，面板会提示原因，菜单栏统计旁显示警示图标；尚未同步到该时段的空结果显示 `—`，避免把未同步误认为真实零用量。已同步的非零值保留并标明为最近同步结果，完整覆盖的历史范围不受来源退出影响。

“重新读取”只读取数据库，不触发 CC Switch 扫描。参考版本的 CC Switch 启动后扫描一次，后台约每 10 分钟扫描一次；打开它的用量页时按页面设置更频繁扫描，且必须启用其自动扫描。详情及源码依据见 [数据源分析](docs/data-sources.md)。

跨本地午夜时，今日、最近 7 天及最近 30 天范围会立即失效并重新读取，即使设置为手动刷新也不会把昨天的快照继续标为今天。跨天前尚未完成的查询不会覆盖新一天的数据；唤醒后同样重新读取。

成本始终汇总 CC Switch 的 `total_cost_usd`，不自行定价；它不等于 Credits 扣款或订阅实付。历史按天归档数据无法恢复任意分钟边界，涉及这类边界时面板会提示。

## 重置动态与图标提示

下拉面板提供“概览”“分析”“重置动态”三个标签页。“概览”集中显示账户、额度与四项统计；其他额度窗口可展开，正常来源时间收进“来源详情”，异常和归档边界提示始终可见。面板按菜单栏所在屏幕的可用高度限高，正文滚动，页头页尾保留。

“分析”展示四类 Token 构成，份额以全部 Token（包含输出）为分母，与仅以全部输入为分母的缓存命中率不同。分析和概览共用同一范围与统计快照；未同步、读取失败和真实零用量分别呈现。本机历史不保证按 ChatGPT 账户拆分，不能视为当前登录账户的账单。

重置动态来自 [AIHOT 的 Tibo 重置监控](https://aihot.news/codex-reset)，展示近期额度重置、重置卡发放、待生效预告、确认状态、适用范围和来源原帖；统一使用北京时间。AIHOT 是第三方整理页面，确认帖的时间不等于个人账户的到账时间，推算窗口也不会当作已确认。

在“设置 → 重置动态”中可分别控制获取动态、菜单栏提示及检查间隔。默认每 10 分钟检查一次；支持 30 分钟、1 小时和手动检查。手动刷新、唤醒及重新启动也遵守至少 10 分钟的请求间隔和服务端要求的重试时间。

首次成功加载已有记录时建立基线，不把历史记录标成新消息。后续新公告、确认、新增来源原帖、实质更正或明确撤回会成为未读动态；仅检查时间、预计窗口或推算状态变化不会反复提醒。

开启提示时，有未读动态的菜单栏图标会变为带标记的铃铛。点击后直接进入“重置动态”，查看后清除提示，恢复普通图标。选择仅显示图标时同样可用。关闭图标提示仍可在标签页查看动态。

消息缓存、已读状态、ETag 与下次允许检查的时间均保存在本机，重启后继续使用。网络故障保留上次缓存并显示错误及来源核对时间，不影响额度和本地统计。最近记录会按来源快照替换，以处理撤回、更正和时间窗滚动；不下载完整历史。

数据协议及更新判定见 [重置动态集成说明](docs/reset-news.md)。

## 开发与验证

```bash
swift test
swift run CodexUsage --diagnose
swift run CodexUsage --diagnose --statistics-only --range all
swift run CodexUsage --diagnose-news
swift run CodexUsage --diagnose-wake
python3 scripts/verify-statistics.py
```

`--diagnose` 返回用量与额度 JSON，不输出邮箱、账户 ID 或凭据。支持 `--database`、`--codex-path`、`--codex-home` 覆盖路径；范围参数可用 `today`、`last24Hours`、`week`、`month`、`all`。

`--diagnose-wake` 在独立进程模拟唤醒恢复，核对额度、统计及账户识别是否自动完成；不使电脑休眠，不改变设置，也不输出邮箱或凭据。更多可扩展数据与本机覆盖率见 [数据扩展清单](docs/data-sources.md)。

`verify-statistics.py` 只读取源库，在系统临时目录中复制统计所需列，以同一份快照对照 CC Switch 的参考查询，完成后删除临时副本。不会复制供应商配置或凭据。

```bash
swift run CodexUsage --settings
swift run CodexUsage --preview build/preview-light.png
swift run CodexUsage --preview build/preview-dark.png --dark
swift run CodexUsage --preview-analysis build/analysis-light.png
swift run CodexUsage --preview-settings build/settings-light.png
swift run CodexUsage --preview-settings build/settings-data.png --section data
swift run CodexUsage --preview-news build/news-light.png
swift run CodexUsage --preview build/unsynced.png --unsynced
```

预览使用明确的示例数据，不会查询账户。`--stale`、`--empty`、`--failed`、`--invalid-range`、`--compact-panel` 可检查相应状态；`swift run CodexUsage --demo --settings` 可操作隔离示例界面，不保存设置或查询账户。运行预览前先创建 `build` 目录，或先运行构建脚本。

代码位于 `Sources/UsageCore`（查询、模型、时间范围）及 `Sources/CodexUsage`（菜单栏、面板、设置）。验证记录见 [验证说明](docs/verification.md)。

发布流程在 `.github/workflows/release.yml`：推送 `vX.Y.Z` 标签或 `release/vX.Y.Z` 发布分支（也可手动指定已存在标签）后，从标签独立检出、测试、打包、校验，附件完整后公开 Release；已有正式版本不会覆盖。版本说明位于 `docs/releases/`。产品打磨的需求、设计、技能适用性与验收记录见 [0.4.0 工作记录](proc/0.4.0-product-polish/skills.md)。

当前打包脚本生成本机架构应用，使用本地 ad-hoc 签名；安装包尚未使用 Developer ID Installer 签名或公证，因此跨机器分发时可能被 Gatekeeper 拦截。尚未配置自动更新。
