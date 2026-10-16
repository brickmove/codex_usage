import XCTest
@testable import UsageCore

final class StatisticsSyncStateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func range() throws -> UsageRange {
        try UsageRange(start: now.addingTimeInterval(-1800), end: now)
    }
    func testClosedSourceEmptyTodayIsNotConfirmedZero() throws {
        var summary = UsageSummary(); summary.lastSyncedAt = now.addingTimeInterval(-14400)
        let state = StatisticsSyncState.evaluate(summary: summary, range: try range(), sourceIsRunning: false, now: now)
        XCTAssertEqual(state, .sourceNotRunning)
        var settings = AppSettings(); settings.menuMetrics = [.cost, .tokens, .requests]
        let presentation = MenuDisplay.presentation(settings: settings, quota: nil, statistics: summary, statisticsSyncState: state)
        XCTAssertEqual(presentation.items.map(\.value), ["—", "—", "—"])
        XCTAssertNotNil(presentation.statisticsNotice)
    }
    func testLaunchingSourceDoesNotConfirmYesterdaysEmptySnapshot() throws {
        var summary = UsageSummary(); summary.lastSyncedAt = now.addingTimeInterval(-14400)
        XCTAssertEqual(StatisticsSyncState.evaluate(summary: summary, range: try range(), sourceIsRunning: true, now: now), .waitingForSync)
    }
    func testRecentSyncCanConfirmActualZero() throws {
        var summary = UsageSummary(); summary.lastSyncedAt = now.addingTimeInterval(-5)
        let state = StatisticsSyncState.evaluate(summary: summary, range: try range(), sourceIsRunning: true, now: now)
        XCTAssertEqual(state, .current)
        var settings = AppSettings(); settings.menuMetrics = [.cost, .tokens, .requests]
        XCTAssertEqual(MenuDisplay.presentation(settings: settings, quota: nil, statistics: summary, statisticsSyncState: state).items.map(\.value), ["$0.00", "0", "0"])
    }
    func testOldNonzeroSnapshotIsKeptButMarkedIncomplete() throws {
        var summary = UsageSummary(); summary.totalRequests = 3; summary.totalCost = 9.25
        summary.lastSyncedAt = now.addingTimeInterval(-1200)
        let state = StatisticsSyncState.evaluate(summary: summary, range: try range(), sourceIsRunning: true, now: now)
        XCTAssertEqual(state, .delayed)
        var settings = AppSettings(); settings.menuMetrics = [.cost]
        let presentation = MenuDisplay.presentation(settings: settings, quota: nil, statistics: summary, statisticsSyncState: state)
        XCTAssertEqual(presentation.items.first?.value, "$9.25")
        XCTAssertNotNil(presentation.statisticsNotice)
    }
    func testCompletedHistoricalRangeRemainsValidWhenSourceIsClosed() throws {
        var summary = UsageSummary(); summary.lastSyncedAt = now.addingTimeInterval(-60)
        let historical = try UsageRange(start: now.addingTimeInterval(-86400), end: now.addingTimeInterval(-3600))
        XCTAssertEqual(StatisticsSyncState.evaluate(summary: summary, range: historical, sourceIsRunning: false, now: now), .current)
    }
    func testProxyRecordsWithoutSyncMetadataCanStillBeCurrent() throws {
        var summary = UsageSummary(); summary.totalRequests = 2; summary.latestRecordAt = now.addingTimeInterval(-5)
        XCTAssertEqual(StatisticsSyncState.evaluate(summary: summary, range: try range(), sourceIsRunning: true, now: now), .current)
    }
    func testIconOnlyAndQuotaOnlyDoNotGainStatisticsWarning() {
        var settings = AppSettings(); settings.menuMetrics = []
        XCTAssertNil(MenuDisplay.presentation(settings: settings, quota: nil, statistics: nil, statisticsSyncState: .sourceNotRunning).statisticsNotice)
        settings.menuMetrics = [.quotaRemaining]
        XCTAssertNil(MenuDisplay.presentation(settings: settings, quota: nil, statistics: nil, statisticsSyncState: .sourceNotRunning).statisticsNotice)
    }
    func testCalendarRangesRefreshAtMidnightButRollingAndCustomRangesDoNot() throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let before = ISO8601DateFormatter().date(from: "2026-10-15T23:59:59+08:00")!
        let after = before.addingTimeInterval(2)
        for preset in [RangePreset.today, .week, .month] {
            let queried = try preset.resolve(now: before, calendar: calendar)
            XCTAssertFalse(preset.needsDayRolloverRefresh(queriedRange: queried, now: before, calendar: calendar))
            XCTAssertTrue(preset.needsDayRolloverRefresh(queriedRange: queried, now: after, calendar: calendar))
        }
        let rolling = try RangePreset.last24Hours.resolve(now: before, calendar: calendar)
        XCTAssertFalse(RangePreset.last24Hours.needsDayRolloverRefresh(queriedRange: rolling, now: after, calendar: calendar))
        XCTAssertFalse(RangePreset.custom.needsDayRolloverRefresh(queriedRange: rolling, now: after, calendar: calendar))
    }
    func testBackgroundSourcePreferenceMigratesDisabledAndPersists() throws {
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).automaticallyStartCCSwitch)
        var settings = AppSettings(); settings.automaticallyStartCCSwitch = true
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).automaticallyStartCCSwitch)
    }
}
