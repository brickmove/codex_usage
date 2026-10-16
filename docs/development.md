# 开发指南

[返回首页](../README.md) · [使用指南](user-guide.md) · [验证记录](verification.md)

完整产品范围与冻结数据契约见 [总体方案 SPEC-1.0](product-plan.md)；从空目录比较本地与云端模型见 [实验说明](experiments/model-comparison.md)。`proc/0.4.0-product-polish` 为历史阶段方案，不代替当前总体方案。

## 环境与结构

需要 macOS 14+、Xcode 命令行工具和 Swift 5.9+。本机验证使用 Apple Silicon、Swift 6.4 和 macOS 27 SDK；部署目标为 macOS 14，旧系统与 Intel 未实机验证。项目使用 SwiftPM，无第三方 Swift 包依赖。

| 目录 | 职责 |
| --- | --- |
| `Sources/UsageCore` | Codex 查询、统计读取、模型、范围与展示策略 |
| `Sources/CodexUsage` | 菜单栏、面板、设置和诊断入口 |
| `Tests` | Core 与 AppModel 回归测试 |
| `Resources` | 应用与安装组件配置 |
| `scripts` | 构建、安装、打包及统计对照验证 |
| `docs/images` | README 图标及经过筛选的示例截图 |

## 获取与构建

```bash
git clone https://github.com/brickmove/codex_usage.git
cd codex_usage
./scripts/build-app.sh
open "build/Artifacts.noindex/Codex Usage.app"
```

构建产物位于不参与 Spotlight 索引的 `build/Artifacts.noindex/Codex Usage.app`，使用本机架构与 ad-hoc 签名。若要查询真实数据，需要 Codex CLI 已登录及 CC Switch 已同步的统计库。

安装到“应用程序”：

```bash
./scripts/install-app.sh
```

更新前先退出旧版；脚本会检查应用标识、签名和运行状态，在 `/Applications/Codex Usage.app` 安装并保留已有设置。

生成 `.pkg` 和 SHA-256 文件：

```bash
./scripts/package-app.sh
```

产物位于 `dist/Codex-Usage-<版本>-<架构>.pkg`，仅包含应用、图标、配置、签名和第三方声明。尚无 Developer ID Installer 签名和公证；没有自动更新。

## 测试与诊断

```bash
swift test
swift run CodexUsage --diagnose
swift run CodexUsage --diagnose --statistics-only --range all
swift run CodexUsage --diagnose-news
swift run CodexUsage --diagnose-wake
python3 scripts/verify-statistics.py
```

- `--diagnose` 输出统计及额度 JSON，不输出邮箱、账户 ID 或凭据。范围支持 `today`、`last24Hours`、`week`、`month`、`all`；路径可由 `--database`、`--codex-path`、`--codex-home` 覆盖。
- `--diagnose-wake` 在独立进程模拟恢复，核对账户、额度和统计可用性；不让电脑休眠，不改变设置，不输出邮箱或凭据。不能以此代替真实硬件休眠测试。
- `--diagnose-news` 遵守新闻缓存与最短请求间隔。
- `verify-statistics.py` 只读源库，在临时目录复制必要统计列，以同一快照对照 CC Switch 参考查询，完成后删除副本；不复制供应商配置或凭据。

当前主分支的 125 项应用测试与 9 项发布规则测试、原生交互和安装包检查结果见 [验证记录](verification.md)。

## 隔离示例与界面截图

```bash
mkdir -p build
swift run CodexUsage --demo --settings
swift run CodexUsage --preview build/overview-light.png
swift run CodexUsage --preview build/overview-dark.png --dark
swift run CodexUsage --preview-analysis build/analysis-light.png
swift run CodexUsage --preview-settings build/settings-menu.png
swift run CodexUsage --preview-settings build/settings-data.png --section data
swift run CodexUsage --preview-settings build/settings-appearance.png --section appearance --theme iris --appearance dark
swift run CodexUsage --preview-news build/reset-news.png
```

示例模式不查询账户，也不保存设置。示例与预览的 `--icon-set standard|filled|circular|minimal` 可切换图标组；`--theme teal|ocean|forest|iris|sand|graphite` 与 `--appearance system|light|dark` 分别选择配色与明暗；`--dark` 保留为预览深色模式的快捷参数。预览可用 `--stale`、`--empty`、`--failed`、`--unsynced`、`--invalid-range`、`--compact-panel` 检查状态。生成截图后须人工检查布局、示例标识和隐私；offscreen 截图不替代真实控件交互或辅助功能验收。

README 截图的版本、来源及复现方式见 [截图说明](images/screenshots/0.5.0/README.md)。`build/` 中的全部 QA 输出保持忽略，仅将筛选的文档资产放入 `docs/images/`；不使用 `git add -f`。临时 QA 应用和安装包解包目录也应放在 `.noindex` 目录内，避免在 Spotlight 中形成重复应用入口；使用后注销其 LaunchServices 注册。

## 发布流程

日常修复只提交、推送代码并更新 [未发布记录](../CHANGELOG.md)，不逐个问题创建版本标签或 Release。两次公开 Release 至少间隔一个自然月，以 GitHub 最新一次 `published_at` 加一个月计算，保留 UTC 时分秒；月末按下月最后一天处理。草稿不计，预发布也计入间隔，防止通过预发布绕过规则。

例如 v0.5.0 于 2026-10-16 公开，下一次最早为 2026-11-16 的对应 UTC 时刻，具体值以工作流实时查询为准。达到间隔后可统一发布累计改动；没有定时自动发版任务。

`.github/workflows/release.yml` 在 `main` 提交时只运行发布规则测试与间隔检查，始终不创建 Release。版本标签、`release/vX.Y.Z` 分支及手动发布也必须先通过同一检查；不满一个月时跳过打包发布任务，接口错误则检查失败并阻止发布，不能将 API 错误当作首次发布。正式上传前再次核对间隔。

符合间隔时，流程从版本标签独立 worktree 检出，检查版本与 arm64，执行测试、打包和校验，再创建草稿、上传附件并公开。已有公开安装包不会被覆盖，发布任务串行执行。Release 标题只使用 `vX.Y.Z`，功能摘要写在正文中。日常本地验证可递增 `CFBundleVersion`；仅统一发版时调整 `CFBundleShortVersionString` 和创建版本标签，既有标签与附件保持不变。

发布门禁使用 Python 标准库，可离线复现：

```bash
python3 -m unittest discover -s Tests/ReleasePolicyTests -v
python3 scripts/release-policy.py --releases-json build/published-releases.json
```

JSON 使用 GitHub Releases API 原始数组，或 `gh api --paginate --slurp` 返回的分页数组。输出 `eligible`、上次版本与最早可发布时间；脚本自身不创建 Release。当前主分支包含未发布的图标组修复，本机验证为 0.5.0 / build 9。

`release-notes.yml` 在主分支发布说明变更或手动触发时，将已有正式 Release 的标题统一为标签名，并同步对应 Markdown 正文；跳过草稿和不存在本地说明的版本，核对附件信息未变。修订说明无需重新构建或移动版本标签。

## 项目记录

- [数据来源与扩展边界](data-sources.md) · [重置动态协议](reset-news.md)。
- [0.4.0 技能、需求与验收记录](../proc/0.4.0-product-polish/skills.md)。
- [技术模式](tech/README.md) · [第三方声明](../THIRD_PARTY_NOTICES.md)。

提交反馈或 PR 时，附修改目的和相应验证。不要提交数据库、认证文件、个人设置、构建输出、日志或未脱敏的截图。
