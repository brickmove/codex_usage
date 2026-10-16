import AppKit
import SwiftUI
import UsageCore

struct MenuIconSettings: View {
    @Binding var settings: AppSettings
    @Binding var error: String?
    @Environment(\.appPalette) private var style

    var body: some View {
        Section("菜单栏图标") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(MenuIconStyle.allCases.filter { $0 != .custom }) { icon in
                    Button { settings.menuIcon = icon; error = nil } label: {
                        HStack(spacing: 6) {
                            Image(systemName: icon.symbolName).frame(width: 19)
                            Text(icon.title)
                            if settings.menuIcon == icon { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                        }.frame(maxWidth: .infinity, minHeight: 28)
                    }.buttonStyle(.bordered)
                        .tint(settings.menuIcon == icon ? style.accent : style.secondary)
                        .accessibilityLabel(icon.title + "图标")
                        .accessibilityValue(settings.menuIcon == icon ? "已选择" : "未选择")
                }
            }
            if let data = settings.customMenuIcon, let image = NSImage(data: data) {
                HStack(spacing: 10) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 28, height: 28)
                        .padding(6).background(style.background, in: RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(settings.customMenuIconName ?? "自定义图标").lineLimit(1).truncationMode(.middle)
                        Text(settings.menuIcon == .custom ? "正在使用 · 已保存副本" : "已保存，可随时切换")
                            .font(.caption).foregroundStyle(style.secondary)
                    }
                    Spacer(minLength: 2)
                    Button(settings.menuIcon == .custom ? "已选用" : "选用") { settings.menuIcon = .custom; error = nil }
                        .disabled(settings.menuIcon == .custom).accessibilityLabel("选用自定义图标")
                    Button("移除") {
                        settings.customMenuIcon = nil; settings.customMenuIconName = nil
                        if settings.menuIcon == .custom { settings.menuIcon = .automatic }
                        error = nil
                    }.accessibilityLabel("移除自定义图标")
                }
            } else if settings.menuIcon == .custom {
                Label("已保存的图标无法读取，当前使用默认图标。请重新导入。", systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button(settings.customMenuIcon == nil ? "导入图片…" : "替换图片…", action: importImage)
                Button("恢复默认图标") {
                    settings.menuIcon = .automatic; settings.menuIconSize = .regular
                    settings.menuIconRendering = .template
                    settings.customMenuIcon = nil; settings.customMenuIconName = nil; error = nil
                }
                Spacer()
                Text("仅保存到本机").font(.caption).foregroundStyle(style.secondary)
            }
            Picker("图标大小", selection: $settings.menuIconSize) {
                ForEach(MenuIconSize.allCases) { Text($0.title).tag($0) }
            }
            if settings.menuIcon == .custom {
                Picker("图标颜色", selection: $settings.menuIconRendering) {
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
            Text("默认沿用指标图标；选定其他样式后会在数值前常驻。未读动态或数据异常时，提示图标会临时替换所选图标。")
                .font(.caption).foregroundStyle(style.secondary).fixedSize(horizontal: false, vertical: true)
        }
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
                settings.customMenuIcon = imported.pngData
                settings.customMenuIconName = String(url.lastPathComponent.prefix(120))
                settings.menuIconRendering = .original
                settings.menuIcon = .custom
                error = nil
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
