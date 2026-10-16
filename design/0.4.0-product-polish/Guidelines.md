# 原生 macOS 设计规范

平台：macOS 14+，SwiftUI / AppKit，跟随系统浅色与深色。保留青色强调和系统背景，系统按钮、Picker、DisclosureGroup、DatePicker，不模拟网页导航。

菜单栏：SF Symbols + 数值；名称、范围和异常在 tooltip / AX 中完整说明。默认项不变。面板宽 400pt，期望高 660pt，以屏幕可用高度限高，固定页头/页签/页尾，正文滚动。

字号：主数字 23–28pt；正文/指标名称 11–13pt；辅助说明统一至少 11pt。正文间距 12–16pt，卡片边距 12–16pt。用层级和留白区分信息，说明不堆叠到首页。

状态：加载有文字，空值与未知分开；来源异常、归档边界不可收进折叠区域。失效额度不显示有意义的条宽或百分比；AX 同样待更新。正常元数据可折叠。颜色之外必须有名称、值、状态文本。

参考：Apple [Settings](https://developer.apple.com/design/human-interface-guidelines/settings)、[Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers)，2026-10-16 检索；分组和布局为本项目设计判断，不冒称 Apple 逐项强制要求。
