import XCTest
@testable import UsageCore

final class MenuDisplayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func quota() throws -> QuotaSnapshot {
        let json = """
        {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":\(now.addingTimeInterval(93600).timeIntervalSince1970)},
        "credits":{"balance":"62197.23","hasCredits":true,"unlimited":false}},"rateLimitResetCredits":{"availableCount":2}}
        """
        return QuotaSnapshot(response: try JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8)), queriedAt: now)
    }
    private func statistics() -> UsageSummary {
        var stats = UsageSummary()
        stats.totalRequests = 1200; stats.totalCost = 12.34
        stats.freshInput = 20; stats.cacheRead = 80; stats.output = 10
        return stats
    }
    private func settings(_ metrics: [MenuMetric]) -> AppSettings {
        var settings = AppSettings(); settings.menuMetrics = metrics; return settings
    }
    func testDefaultLayoutNamesQuotaBalanceAndReset() throws {
        XCTAssertEqual(MenuDisplay.title(settings: AppSettings(), quota: try quota(), statistics: nil, now: now),
                       "每周剩余 80% · Credits 62.2K · 1 天 2 小时后重置")
        let presentation = MenuDisplay.presentation(settings: AppSettings(), quota: try quota(), statistics: nil, now: now)
        XCTAssertEqual(presentation.items.map(\.value), ["80%", "62.2K", "1d2h"])
        XCTAssertEqual(presentation.items.map { $0.metric.symbolName },
                       ["gauge.with.dots.needle.50percent", "creditcard", "clock.arrow.circlepath"])
    }
    func testCustomOrderAndChoiceAreHonored() throws {
        let s = settings([.requests, .credits, .quotaRemaining])
        XCTAssertEqual(MenuDisplay.title(settings: s, quota: try quota(), statistics: statistics(), now: now),
                       "今日请求 1.2K 次 · Credits 62.2K · 每周剩余 80%")
        let presentation = MenuDisplay.presentation(settings: s, quota: try quota(), statistics: statistics(), now: now)
        XCTAssertEqual(presentation.items.map(\.metric), s.menuMetrics)
        XCTAssertEqual(presentation.items.map(\.value), ["1.2K", "62.2K", "80%"])
    }
    func testStatisticsOnlyDisplayWorksWithoutQuota() {
        let title = MenuDisplay.title(settings: settings([.cost, .tokens, .requests, .cacheHitRate]),
                                      quota: nil, statistics: statistics(), now: now, quotaIsStale: true)
        XCTAssertEqual(title, "今日费用 $12.34 · 今日用量 110 Tokens · 今日请求 1.2K 次 · 今日缓存命中 80%")
    }
    func testLoadingQuotaDoesNotHideStatistics() {
        let title = MenuDisplay.title(settings: settings([.quotaRemaining, .requests]), quota: nil,
                                      statistics: statistics(), now: now, loadingQuota: true)
        XCTAssertEqual(title, "额度剩余 … · 今日请求 1.2K 次")
    }
    func testQuotaUsedAndResetCountCanBeSelected() throws {
        XCTAssertEqual(MenuDisplay.title(settings: settings([.quotaUsed, .availableResets]), quota: try quota(),
                                        statistics: nil, now: now), "每周已用 20% · 可用重置 2 次")
    }
    func testStaleQuotaDoesNotHideGoodStatisticsOrShowOldBalance() throws {
        let title = MenuDisplay.title(settings: settings([.credits, .cost]), quota: try quota(),
                                      statistics: statistics(), now: now, quotaIsStale: true)
        XCTAssertEqual(title, "Credits — · 今日费用 $12.34 · 额度待更新")
        let items = MenuDisplay.presentation(settings: settings([.credits, .cost]), quota: try quota(),
                                             statistics: statistics(), now: now, quotaIsStale: true).items
        XCTAssertEqual(items.map(\.value), ["—", "$12.34"])
    }
    func testFailedStatisticsDoNotShowOldCostOrHideQuota() throws {
        XCTAssertEqual(MenuDisplay.title(settings: settings([.cost, .quotaRemaining]), quota: try quota(),
                                        statistics: statistics(), now: now, statisticsFailed: true),
                       "今日费用 — · 每周剩余 80% · 统计不可用")
    }
    func testStatisticScopeFollowsSelectedRange() {
        var s = settings([.cost]); s.range = .week
        XCTAssertEqual(MenuDisplay.title(settings: s, quota: nil, statistics: statistics()), "近7天费用 $12.34")
        s.range = .custom
        XCTAssertEqual(MenuDisplay.title(settings: s, quota: nil, statistics: statistics()), "所选时段费用 $12.34")
        XCTAssertEqual(MenuDisplay.presentation(settings: s, quota: nil, statistics: statistics()).items.first?.value, "$12.34")
    }
    func testUnavailableStatisticsAreNotRepresentedAsZero() {
        XCTAssertEqual(MenuDisplay.title(settings: settings([.requests, .cacheHitRate]), quota: nil, statistics: nil),
                       "今日请求 — 次 · 今日缓存命中 —")
        XCTAssertEqual(MenuDisplay.title(settings: settings([.requests, .cacheHitRate]), quota: nil, statistics: UsageSummary()),
                       "今日请求 0 次 · 今日缓存命中 —")
    }
    func testIconOnlyIgnoresLoadingAndErrors() {
        XCTAssertEqual(MenuDisplay.title(settings: settings([]), quota: nil, statistics: nil,
                                        loadingQuota: true, loadingStatistics: true, statisticsFailed: true), "")
        XCTAssertTrue(MenuDisplay.presentation(settings: settings([]), quota: nil, statistics: nil).items.isEmpty)
    }
    func testSelectionAndReorderingPreserveUniqueMetrics() {
        var s = settings([.cost, .requests])
        s.setMenuMetric(.tokens, enabled: true); s.setMenuMetric(.cost, enabled: true)
        XCTAssertEqual(s.menuMetrics, [.cost, .requests, .tokens])
        s.moveMenuMetric(.tokens, by: -1)
        XCTAssertEqual(s.menuMetrics, [.cost, .tokens, .requests])
        s.moveMenuMetric(.cost, by: -1); s.moveMenuMetric(.requests, by: 1)
        s.setMenuMetric(.cost, enabled: false)
        XCTAssertEqual(s.menuMetrics, [.tokens, .requests])
    }
    func testLegacySettingsMigrateVisibilityWithoutResettingOtherPreferences() throws {
        var previous = AppSettings()
        previous.databasePath = "/custom/cc-switch.db"; previous.codexPath = "/custom/codex"
        previous.range = .month; previous.quotaInterval = 600
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(previous)) as? [String: Any])
        json.removeValue(forKey: "menuMetrics")
        json["showCreditsInMenu"] = false; json["showResetInMenu"] = true
        let migrated = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(migrated.menuMetrics, [.quotaRemaining, .resetCountdown])
        XCTAssertEqual(migrated.databasePath, previous.databasePath)
        XCTAssertEqual(migrated.codexPath, previous.codexPath)
        XCTAssertEqual(migrated.range, .month); XCTAssertEqual(migrated.quotaInterval, 600)
    }
    func testUnknownAndDuplicateMetricsDoNotBreakPreferences() throws {
        let data = Data(#"{"menuMetrics":["credits","futureMetric","credits","tokens"],"range":"week"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.menuMetrics, [.credits, .tokens]); XCTAssertEqual(decoded.range, .week)
    }
    func testExplicitIconOnlyTakesPriorityOverLegacyFlags() throws {
        let data = Data(#"{"menuMetrics":[],"showCreditsInMenu":true,"showResetInMenu":true}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: data).menuMetrics.isEmpty)
    }
    func testCustomOrderAndIconOnlySurviveRelaunch() throws {
        let suite = "CodexUsageTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var s = settings([.cost, .quotaUsed, .requests])
        s.save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults).menuMetrics, s.menuMetrics)
        s.menuMetrics = []; s.save(to: defaults)
        XCTAssertTrue(AppSettings.load(from: defaults).menuMetrics.isEmpty)
    }
}
