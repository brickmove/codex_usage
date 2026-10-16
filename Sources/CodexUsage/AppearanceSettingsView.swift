import AppKit
import SwiftUI
import UsageCore

struct MenuIconSettings: View {
    @Binding var settings: AppSettings
    @Binding var error: String?
    @Binding var target: String
    @Environment(\.appPalette) private var style
    private var selectedMetric: MenuMetric { MenuMetric(rawValue: target) ?? .quotaRemaining }
    private var configuration: Binding<MenuMetricIcon> {
        Binding(get: { settings.icon(for: selectedMetric) },
                set: { settings.setIcon($0, for: selectedMetric) })
    }
    private var icon: MenuMetricIcon { configuration.wrappedValue }

    @ViewBuilder var body: some View {
        Section("图标组") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(MenuIconSet.allCases) { set in
                    Button { settings.selectIconSet(set); error = nil } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 12) {
                                ForEach([MenuMetric.quotaRemaining, .credits, .resetCountdown]) { metric in
                                    if let image = MenuBarIcon.groupImage(set, metric: metric, size: .compact) {
                                        Image(nsImage: image).renderingMode(.template).frame(width: 20, height: 20)
                                    }
                                }
                            }.accessibilityHidden(true)
                            HStack {
                                Text(set.title)
                                Spacer()
                                if settings.menuIconSet == set { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                            }
                        }.frame(maxWidth: .infinity).padding(4)
                    }.buttonStyle(.bordered)
                        .tint(settings.menuIconSet == set ? style.accent : style.secondary)
                        .accessibilityLabel(set.title + "图标组")
                        .accessibilityValue(settings.menuIconSet == set ? "已选择" : "未选择")
                }
            }
            Picker("整组图标大小", selection: $settings.menuIconSize) {
                ForEach(MenuIconSize.allCases) { Text($0.title).tag($0) }
            }
            Text("额度、Credits、倒计时等保留各自图形，整组统一切换风格。选择图标组时会清除单项覆盖。")
                .font(.caption).foregroundStyle(style.secondary)
            Button("恢复默认图标组") { settings.resetMetricIcons(); error = nil }
        }
        Section {
            DisclosureGroup("单独自定义指标图标（可选）") {
                Picker("应用到", selection: $target) {
                    ForEach(MenuMetric.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Text("仅覆盖“\(selectedMetric.title)”的图标；选择“跟随图标组”可恢复此项。")
                    .font(.caption).foregroundStyle(style.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(MenuIconStyle.allCases.filter { $0 != .custom }) { choice in
                        Button { configuration.wrappedValue.style = choice; error = nil } label: {
                            HStack(spacing: 6) {
                                Image(systemName: choice.symbolName).frame(width: 19)
                                Text(choice == .automatic ? "跟随图标组" : choice.title)
                                if icon.style == choice { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                            }.frame(maxWidth: .infinity, minHeight: 28)
                        }.buttonStyle(.bordered)
                            .tint(icon.style == choice ? style.accent : style.secondary)
                            .accessibilityLabel(selectedMetric.title + (choice == .automatic ? "跟随图标组" : choice.title + "图标"))
                            .accessibilityValue(icon.style == choice ? "已选择" : "未选择")
                    }
                }
                if let data = icon.imageData, let image = NSImage(data: data) {
                    HStack(spacing: 10) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 28, height: 28)
                            .padding(6).background(style.background, in: RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(icon.imageName ?? "自定义图标").lineLimit(1).truncationMode(.middle)
                            Text(icon.style == .custom ? "正在使用 · 已保存副本" : "已保存，可随时切换")
                                .font(.caption).foregroundStyle(style.secondary)
                        }
                        Spacer(minLength: 2)
                        Button(icon.style == .custom ? "已选用" : "选用") { configuration.wrappedValue.style = .custom; error = nil }
                            .disabled(icon.style == .custom).accessibilityLabel("选用自定义图标")
                        Button("移除") {
                            var updated = icon; updated.imageData = nil; updated.imageName = nil
                            if updated.style == .custom { updated.style = .automatic }
                            configuration.wrappedValue = updated; error = nil
                        }.accessibilityLabel("移除自定义图标")
                    }
                } else if icon.style == .custom {
                    Label("已保存的图标无法读取，当前使用默认图标。请重新导入。", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button(icon.imageData == nil ? "导入图片…" : "替换图片…", action: importImage)
                    Button("跟随图标组") {
                        settings.metricIcons.removeValue(forKey: selectedMetric.rawValue); error = nil
                    }
                    Spacer()
                    Text("仅保存到本机").font(.caption).foregroundStyle(style.secondary)
                }
                Picker("图标大小", selection: configuration.size) {
                    ForEach(MenuIconSize.allCases) { Text($0.title).tag($0) }
                }
                if icon.style == .custom {
                    Picker("图标颜色", selection: configuration.rendering) {
                        ForEach(MenuIconRendering.allCases) { Text($0.title).tag($0) }
                    }
                    Text("导入后默认保留原色。透明底单色图可切换为自动适配明暗，彩色或带底色的图片建议保留原色。")
                        .font(.caption).foregroundStyle(style.secondary)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true).accessibilityLabel("图标导入失败：" + error)
                }
                Text("支持 PNG、JPEG、TIFF、HEIC/HEIF、PDF、ICNS，最大 10 MB、最长边 4096 px；PDF 取首页。推荐透明底方形图，32 / 36 / 40 px 可对应 Retina 尺寸，更大图片会等比缩放。")
                    .font(.caption).foregroundStyle(style.secondary).fixedSize(horizontal: false, vertical: true)
                Text("单项覆盖只用于个别自定义图片或样式；通常只需选择上方图标组。未读动态和数据异常独立提示，保留各指标图标。")
                    .font(.caption).foregroundStyle(style.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.onChange(of: target) { _, _ in error = nil }
    }

    private func importImage() {
        let panel = NSOpenPanel()
        panel.title = "选择菜单栏图标"; panel.prompt = "使用图标"
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MenuIconImporter.allowedTypes
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let imported = try MenuIconImporter.read(url)
                var updated = icon
                updated.imageData = imported.pngData; updated.imageName = String(url.lastPathComponent.prefix(120))
                updated.rendering = .original; updated.style = .custom
                configuration.wrappedValue = updated; error = nil
            } catch { self.error = error.localizedDescription }
        }
        if let window = NSApp.keyWindow { panel.beginSheetModal(for: window, completionHandler: completion) }
        else { panel.begin(completionHandler: completion) }
    }
}

struct AppearanceSettings: View {
    @Binding var settings: AppSettings
    @Environment(\.appPalette) private var style
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Section("外观模式") {
            Picker("外观模式", selection: $settings.appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            Text("控制面板与设置窗口的明暗；菜单栏遵循 macOS 外观，自定义图标也可保留原色。")
                .font(.caption).foregroundStyle(style.secondary)
        }
        Section("主题配色") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(AppTheme.allCases) { theme in
                    themeButton(theme)
                }
            }
            Text("切换后立即预览。保存后应用到概览、分析、重置动态与设置，取消则保留原主题。")
                .font(.caption).foregroundStyle(style.secondary)
        }
        Section("效果预览 · 示例数据") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("每周额度", systemImage: "gauge.with.dots.needle.50percent").font(.callout)
                    Spacer()
                    Text("80%").font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                }
                GeometryReader { geometry in
                    Capsule().fill(style.hairline)
                    Capsule().fill(style.accent).frame(width: geometry.size.width * 0.8)
                }.frame(height: 6).accessibilityHidden(true)
                HStack {
                    Text("用量 1.07B Tokens")
                    Spacer()
                    Text("6 天后重置")
                }.font(.caption).foregroundStyle(style.secondary)
            }.padding(14).panelCard()
                .accessibilityElement(children: .combine)
            Button("恢复默认外观") { settings.theme = .teal; settings.appearance = .system }
        }
    }

    private func themeButton(_ theme: AppTheme) -> some View {
        let palette = ThemePalette(theme: theme, dark: colorScheme == .dark)
        let selected = settings.theme == theme
        return Button { settings.theme = theme } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 5).fill(palette.card)
                    RoundedRectangle(cornerRadius: 5).fill(palette.accent)
                    RoundedRectangle(cornerRadius: 5).fill(palette.secondary)
                }.frame(height: 23).accessibilityHidden(true)
                HStack {
                    Text(theme.title).font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? palette.accent : palette.secondary)
                }.foregroundStyle(palette.text)
            }.padding(10).background(palette.background, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.bordered).tint(selected ? palette.accent : style.hairline)
            .accessibilityLabel(theme.title + "主题").accessibilityValue(selected ? "已选择" : "未选择")
    }
}
