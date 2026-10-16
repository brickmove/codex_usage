import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public static var preferences: UserDefaults {
        // Raw SwiftPM runs and the .app must share preferences. Keep QA isolated.
        let domain = Bundle.main.bundleIdentifier == "local.codexusage.qa" ? "local.codexusage.qa" : "local.codexusage.menubar"
        if Bundle.main.bundleIdentifier == domain { return .standard }
        return UserDefaults(suiteName: domain) ?? .standard
    }
    public var databasePath = "~/.cc-switch/cc-switch.db"
    public var codexPath = ""
    public var codexHome = ""
    public var quotaInterval: TimeInterval = 300
    public var statisticsInterval: TimeInterval = 30
    public var automaticallyStartCCSwitch = false
    public var range: RangePreset = .today
    public var customStart = Calendar.current.startOfDay(for: Date())
    public var customEnd = Date()
    public var menuMetrics: [MenuMetric] = MenuMetric.defaults
    public var menuIcon: MenuIconStyle = .automatic
    public var menuIconSize: MenuIconSize = .regular
    public var menuIconRendering: MenuIconRendering = .template
    public var customMenuIcon: Data?
    public var customMenuIconName: String?
    public var theme: AppTheme = .teal
    public var appearance: AppAppearance = .system
    public var resetNewsEnabled = true
    public var showResetNewsIndicator = true
    public var resetNewsInterval: TimeInterval = 600
    public init() {}

    enum CodingKeys: String, CodingKey {
        case databasePath, codexPath, codexHome, quotaInterval, statisticsInterval, automaticallyStartCCSwitch
        case range, customStart, customEnd, menuMetrics, resetNewsEnabled, showResetNewsIndicator, resetNewsInterval
        case menuIcon, menuIconSize, menuIconRendering, customMenuIcon, customMenuIconName, theme, appearance
    }
    private enum LegacyKeys: String, CodingKey { case showCreditsInMenu, showResetInMenu }

    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        databasePath = try c.decodeIfPresent(String.self, forKey: .databasePath) ?? databasePath
        codexPath = try c.decodeIfPresent(String.self, forKey: .codexPath) ?? codexPath
        codexHome = try c.decodeIfPresent(String.self, forKey: .codexHome) ?? codexHome
        quotaInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .quotaInterval) ?? quotaInterval
        statisticsInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .statisticsInterval) ?? statisticsInterval
        automaticallyStartCCSwitch = try c.decodeIfPresent(Bool.self, forKey: .automaticallyStartCCSwitch) ?? automaticallyStartCCSwitch
        range = try c.decodeIfPresent(RangePreset.self, forKey: .range) ?? range
        customStart = try c.decodeIfPresent(Date.self, forKey: .customStart) ?? customStart
        customEnd = try c.decodeIfPresent(Date.self, forKey: .customEnd) ?? customEnd
        // A newer theme/icon identifier must not discard existing paths or metric preferences.
        menuIcon = (try? c.decode(String.self, forKey: .menuIcon)).flatMap(MenuIconStyle.init(rawValue:)) ?? menuIcon
        menuIconSize = (try? c.decode(Int.self, forKey: .menuIconSize)).flatMap(MenuIconSize.init(rawValue:)) ?? menuIconSize
        menuIconRendering = (try? c.decode(String.self, forKey: .menuIconRendering)).flatMap(MenuIconRendering.init(rawValue:)) ?? menuIconRendering
        customMenuIcon = try? c.decode(Data.self, forKey: .customMenuIcon)
        customMenuIconName = try? c.decode(String.self, forKey: .customMenuIconName)
        theme = (try? c.decode(String.self, forKey: .theme)).flatMap(AppTheme.init(rawValue:)) ?? theme
        appearance = (try? c.decode(String.self, forKey: .appearance)).flatMap(AppAppearance.init(rawValue:)) ?? appearance
        resetNewsEnabled = try c.decodeIfPresent(Bool.self, forKey: .resetNewsEnabled) ?? resetNewsEnabled
        showResetNewsIndicator = try c.decodeIfPresent(Bool.self, forKey: .showResetNewsIndicator) ?? showResetNewsIndicator
        resetNewsInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .resetNewsInterval) ?? resetNewsInterval
        if let names = try c.decodeIfPresent([String].self, forKey: .menuMetrics) {
            var seen = Set<MenuMetric>()
            menuMetrics = names.compactMap(MenuMetric.init(rawValue:)).filter { seen.insert($0).inserted }
        } else {
            // Preserve the previous version's visibility choices without resetting paths or ranges.
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            menuMetrics = [.quotaRemaining]
            if try legacy.decodeIfPresent(Bool.self, forKey: .showCreditsInMenu) ?? true { menuMetrics.append(.credits) }
            if try legacy.decodeIfPresent(Bool.self, forKey: .showResetInMenu) ?? true { menuMetrics.append(.resetCountdown) }
        }
    }
    public mutating func setMenuMetric(_ metric: MenuMetric, enabled: Bool) {
        if enabled {
            if !menuMetrics.contains(metric) { menuMetrics.append(metric) }
        } else { menuMetrics.removeAll { $0 == metric } }
    }
    public mutating func moveMenuMetric(_ metric: MenuMetric, by offset: Int) {
        guard let index = menuMetrics.firstIndex(of: metric), menuMetrics.indices.contains(index + offset) else { return }
        menuMetrics.swapAt(index, index + offset)
    }
    public mutating func moveMenuMetric(_ metric: MenuMetric, to destination: Int) {
        guard let index = menuMetrics.firstIndex(of: metric), menuMetrics.indices.contains(destination), index != destination else { return }
        menuMetrics.remove(at: index)
        menuMetrics.insert(metric, at: destination)
    }
    public func resolvedRange(now: Date = Date()) throws -> UsageRange {
        try range.resolve(now: now, start: customStart, end: customEnd)
    }
    public static func load(from defaults: UserDefaults = AppSettings.preferences) -> AppSettings {
        guard let data = defaults.data(forKey: "appSettings"),
              var value = try? JSONDecoder().decode(AppSettings.self, from: data) else { return AppSettings() }
        // Corrupt preferences must not create a hot polling loop.
        value.quotaInterval = value.quotaInterval > 0 ? max(60, value.quotaInterval) : 0
        value.statisticsInterval = value.statisticsInterval > 0 ? max(15, value.statisticsInterval) : 0
        value.resetNewsInterval = value.resetNewsInterval > 0 ? max(ResetNewsSource.minimumInterval, value.resetNewsInterval) : 0
        return value
    }
    public func save(to defaults: UserDefaults = AppSettings.preferences) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "appSettings") }
    }
    public static func expandedPath(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }
}
