import Foundation

public enum AppTheme: String, Codable, CaseIterable, Identifiable, Sendable {
    case teal, ocean, forest, iris, sand, graphite
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .teal: return "青碧"
        case .ocean: return "海洋"
        case .forest: return "森林"
        case .iris: return "鸢尾"
        case .sand: return "暖沙"
        case .graphite: return "石墨"
        }
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

public enum MenuIconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, gauge, terminal, bolt, sparkles, chart, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .automatic: return "默认"
        case .gauge: return "仪表"
        case .terminal: return "终端"
        case .bolt: return "闪电"
        case .sparkles: return "星光"
        case .chart: return "图表"
        case .custom: return "自定义"
        }
    }
    public var symbolName: String {
        switch self {
        case .automatic, .gauge, .custom: return "gauge.with.dots.needle.50percent"
        case .terminal: return "terminal"
        case .bolt: return "bolt.fill"
        case .sparkles: return "sparkles"
        case .chart: return "chart.bar.xaxis"
        }
    }
}

public enum MenuIconSize: Int, Codable, CaseIterable, Identifiable, Sendable {
    case compact = 16, regular = 18, large = 20
    public var id: Int { rawValue }
    public var title: String {
        switch self {
        case .compact: return "16 pt · 紧凑"
        case .regular: return "18 pt · 标准"
        case .large: return "20 pt · 较大"
        }
    }
}

public enum MenuIconRendering: String, Codable, CaseIterable, Identifiable, Sendable {
    case template, original
    public var id: String { rawValue }
    public var title: String { self == .template ? "自动适配明暗" : "保留原色" }
}
