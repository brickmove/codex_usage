# 0.5.0 界面截图

由 Codex Usage 0.5.0 / build 8 的最终 Release 二进制生成，使用原生 SwiftUI / AppKit 渲染，保留原始 PNG。账户 `you@example.com`、额度、费用、Token 与重置动态均为内置示例；不含用户自定义图标或真实账户信息，也不是官方公告实录。设置截图标有示例模式，不会保存到正式应用。

| 文件 | 内容与配色 |
| --- | --- |
| `overview-light.png` | 概览，青碧浅色 |
| `overview-dark.png` | 概览，鸢尾深色 |
| `analysis-light.png` | Token 分析，海洋浅色 |
| `reset-news.png` | 示例动态，森林浅色 |
| `settings-menu.png` | 图标选择与导入入口，暖沙浅色 |
| `settings-appearance.png` | 六套主题与明暗模式，鸢尾深色 |
| `unsynced.png` | 分析页等待同步，青碧浅色 |

在仓库根目录构建后复现，输出路径可换成 `build/` 下的临时目录：

```bash
./scripts/build-app.sh
"build/Artifacts.noindex/Codex Usage.app/Contents/MacOS/CodexUsage" --preview build/overview-light.png --theme teal --appearance light
"build/Artifacts.noindex/Codex Usage.app/Contents/MacOS/CodexUsage" --preview build/overview-dark.png --theme iris --appearance dark
"build/Artifacts.noindex/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-analysis build/analysis-light.png --theme ocean --appearance light
"build/Artifacts.noindex/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-news build/reset-news.png --theme forest --appearance light
"build/Artifacts.noindex/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-settings build/settings-menu.png --theme sand --appearance light
"build/Artifacts.noindex/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-settings build/settings-appearance.png --section appearance --theme iris --appearance dark
"build/Artifacts.noindex/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-analysis build/unsynced.png --unsynced --theme teal --appearance light
```

另在 `build/appearance-review/` 检查六套主题 × 浅深色共 12 张概览，以及分析、动态、未同步、过期等状态。原生窗口另验证图标文件选择、主题草稿取消、拖动与箭头排序、保存重开；PNG 不替代真实交互，详见 [验证记录](../../../verification.md)。
