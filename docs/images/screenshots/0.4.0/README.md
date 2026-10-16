# 0.4.0 界面截图

用于项目首页和使用指南，均由 Codex Usage 0.4.0 / build 7 的原生 SwiftUI / AppKit 界面生成。示例账户为 `you@example.com`；费用、Token、额度与消息均为应用内置示例，不是用户真实数据。重置动态是演示预告/确认状态，不是官方公告实录。

图像保持原始 PNG，不拼接或重绘控件。概览、分析、菜单栏设置和未同步截图来自 2026-10-16 09:46 的最终 Release 二进制预览；重置动态于同日补充生成。更新时间和倒计时随生成时间变化。

在仓库根目录执行，先构建应用，再运行：

```bash
./scripts/build-app.sh
mkdir -p build/readme-screenshots
"build/Codex Usage.app/Contents/MacOS/CodexUsage" --preview build/readme-screenshots/overview-light.png
"build/Codex Usage.app/Contents/MacOS/CodexUsage" --preview build/readme-screenshots/overview-dark.png --dark
"build/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-analysis build/readme-screenshots/analysis-light.png
"build/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-news build/readme-screenshots/reset-news.png
"build/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-settings build/readme-screenshots/settings-menu.png
"build/Codex Usage.app/Contents/MacOS/CodexUsage" --preview-analysis build/readme-screenshots/unsynced.png --unsynced
```

检查后将需要的图片复制到此目录。当前 `unsynced.png` 展示分析页的等待同步状态。应用图标位于上两级的 `app-icon.png`，来自同一构建生成的 `build/AppIcon.iconset/icon_128x128@2x.png`。

截图仅作为文档示意；原生控件的实际选中状态、键盘操作及辅助功能另有交互验收，见 [验证记录](../../../verification.md)。
