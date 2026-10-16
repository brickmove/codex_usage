import SwiftUI
import AppKit
import UsageCore

/// Every theme has distinct surfaces as well as an accent. Text tokens remain readable in both appearances.
struct ThemePalette {
    let backgroundHex: UInt32
    let cardHex: UInt32
    let accentHex: UInt32
    let textHex: UInt32
    let secondaryHex: UInt32
    let borderHex: UInt32

    init(theme: AppTheme = .teal, dark: Bool = false) {
        let values: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
        switch (theme, dark) {
        case (.teal, false): values = (0xF0F7F7, 0xFFFFFF, 0x067783, 0x162C30, 0x4C6469, 0xD1E3E5)
        case (.teal, true): values = (0x101E22, 0x1B2C31, 0x65D2DB, 0xEEF7F8, 0xB1C5C9, 0x344B51)
        case (.ocean, false): values = (0xEEF4FC, 0xFFFFFF, 0x2459B8, 0x172A46, 0x50617C, 0xD2DFF2)
        case (.ocean, true): values = (0x111D30, 0x1B2B43, 0x8AB9FF, 0xEFF5FF, 0xB2C4DF, 0x354D70)
        case (.forest, false): values = (0xF1F7EF, 0xFFFFFF, 0x27673C, 0x213625, 0x51694F, 0xD5E4D0)
        case (.forest, true): values = (0x121F18, 0x203327, 0x86D69C, 0xEFF8F0, 0xB5CDBA, 0x385840)
        case (.iris, false): values = (0xF5F1FA, 0xFFFFFF, 0x7142AD, 0x30233F, 0x6E5A7E, 0xE1D7EF)
        case (.iris, true): values = (0x21182C, 0x32243F, 0xC4A5F5, 0xF8F1FF, 0xCDB9DE, 0x574169)
        case (.sand, false): values = (0xFAF4E9, 0xFFFDFA, 0x8B5722, 0x3C2D1C, 0x74604B, 0xE9DCC6)
        case (.sand, true): values = (0x261E18, 0x382D23, 0xE9BA7C, 0xFFF5E8, 0xD3BEA5, 0x5D4A36)
        case (.graphite, false): values = (0xF1F2F4, 0xFFFFFF, 0x475467, 0x202630, 0x596371, 0xD7DCE3)
        case (.graphite, true): values = (0x17191E, 0x252931, 0xBCC8DA, 0xF3F5F8, 0xB8C0CE, 0x434B5A)
        }
        (backgroundHex, cardHex, accentHex, textHex, secondaryHex, borderHex) = values
    }

    var background: Color { Color(hex: backgroundHex) }
    var card: Color { Color(hex: cardHex) }
    var accent: Color { Color(hex: accentHex) }
    var text: Color { Color(hex: textHex) }
    var secondary: Color { Color(hex: secondaryHex) }
    var hairline: Color { Color(hex: borderHex) }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

private struct ThemePaletteKey: EnvironmentKey { static let defaultValue = ThemePalette() }
extension EnvironmentValues {
    var appPalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

struct ThemeContainer<Content: View>: View {
    let theme: AppTheme
    let appearance: AppAppearance
    @Environment(\.colorScheme) private var systemScheme
    @ViewBuilder let content: () -> Content

    var body: some View {
        let scheme = appearance.colorScheme ?? systemScheme
        let palette = ThemePalette(theme: theme, dark: scheme == .dark)
        content()
            .foregroundStyle(palette.text)
            .background(palette.background)
            .tint(palette.accent)
            .environment(\.appPalette, palette)
            .environment(\.colorScheme, scheme)
            .preferredColorScheme(appearance.colorScheme)
    }
}

private struct PanelCard: ViewModifier {
    @Environment(\.appPalette) private var style
    func body(content: Content) -> some View {
        content.background(style.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.hairline, lineWidth: 1))
    }
}

extension View {
    func panelCard() -> some View { modifier(PanelCard()) }
}
