import XCTest
@testable import UsageCore

final class PanelPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func snapshot(_ json: String) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8))
        return QuotaSnapshot(response: response, queriedAt: now)
    }

    private func fundedSnapshot() throws -> QuotaSnapshot {
        try snapshot("""
        {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":1800003600},
        "credits":{"balance":"100","hasCredits":true,"unlimited":false}},
        "rateLimitResetCredits":{"availableCount":2,"credits":[
        {"status":"available","expiresAt":1800007200}]}}
        """)
    }

    func testCurrentWindowExposesMatchingValuesAndProgress() throws {
        let window = RateWindow(usedPercent: 20, windowDurationMins: 10080,
                                resetsAt: now.addingTimeInterval(3600).timeIntervalSince1970)
        let presentation = RateWindowPresentation(window: window, now: now, quotaIsStale: false)
        XCTAssertTrue(presentation.isCurrent)
        XCTAssertEqual(presentation.remainingText, "80%")
        XCTAssertEqual(presentation.usedText, "已用 20%")
        XCTAssertEqual(try XCTUnwrap(presentation.progress), 0.8, accuracy: 0.0001)
        XCTAssertTrue(presentation.accessibilitySummary.contains("80%"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("自动重置"), "合并 AX 文本仍应包含绝对重置日期")
    }

    func testStaleWindowHidesOldNumbersFromTextProgressAndAccessibility() {
        let window = RateWindow(usedPercent: 20, windowDurationMins: 10080,
                                resetsAt: now.addingTimeInterval(3600).timeIntervalSince1970)
        let presentation = RateWindowPresentation(window: window, now: now, quotaIsStale: true)
        XCTAssertFalse(presentation.isCurrent)
        XCTAssertEqual(presentation.remainingText, "—")
        XCTAssertEqual(presentation.usedText, "额度待更新")
        XCTAssertNil(presentation.progress)
        XCTAssertFalse(presentation.accessibilitySummary.contains("%"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("待更新"))
        XCTAssertFalse(presentation.accessibilitySummary.contains("自动重置"), "过期快照不向 AX 暴露旧重置日期")
    }

    func testSecondaryWindowExpiresAtResetWithoutInvalidatingCurrentSibling() {
        let weekly = RateWindow(usedPercent: 20, windowDurationMins: 10080,
                                resetsAt: now.addingTimeInterval(3600).timeIntervalSince1970)
        for reset in [now, now.addingTimeInterval(-1)] {
            let secondary = RateWindow(usedPercent: 55, windowDurationMins: 300,
                                       resetsAt: reset.timeIntervalSince1970)
            let expired = RateWindowPresentation(window: secondary, now: now, quotaIsStale: false)
            XCTAssertFalse(expired.isCurrent)
            XCTAssertEqual(expired.remainingText, "—")
            XCTAssertEqual(expired.usedText, "额度待更新")
            XCTAssertNil(expired.progress)
            XCTAssertFalse(expired.accessibilitySummary.contains("%"))
        }
        XCTAssertTrue(RateWindowPresentation(window: weekly, now: now, quotaIsStale: false).isCurrent)
    }

    func testCurrentAccountShowsStoredCreditsAndAvailableResetDetails() throws {
        let presentation = AccountQuotaPresentation(snapshot: try fundedSnapshot(), now: now, isStale: false)
        XCTAssertEqual(presentation.creditsText, "100")
        XCTAssertNotNil(presentation.estimatedValueText)
        XCTAssertEqual(presentation.availableResetsText, "2 次")
        XCTAssertNotNil(presentation.nextExpiryText)
    }

    func testStaleAccountHidesBalanceEstimateResetCountAndExpiry() throws {
        let presentation = AccountQuotaPresentation(snapshot: try fundedSnapshot(), now: now, isStale: true)
        XCTAssertEqual(presentation.creditsText, "—")
        XCTAssertNil(presentation.estimatedValueText)
        XCTAssertEqual(presentation.availableResetsText, "—")
        XCTAssertNil(presentation.nextExpiryText)
    }

    func testUnlimitedAndMissingCreditsRemainDistinctFromZero() throws {
        let unlimited = try snapshot("""
        {"rateLimits":{"credits":{"unlimited":true,"hasCredits":true}}}
        """)
        let unlimitedPresentation = AccountQuotaPresentation(snapshot: unlimited, now: now, isStale: false)
        XCTAssertEqual(unlimitedPresentation.creditsText, "不限量")
        XCTAssertNil(unlimitedPresentation.estimatedValueText)
        let missing = AccountQuotaPresentation(snapshot: try snapshot("{}"), now: now, isStale: false)
        XCTAssertEqual(missing.creditsText, "未提供")
        XCTAssertNil(missing.estimatedValueText)
        XCTAssertNil(missing.nextExpiryText)
        let zero = try snapshot("""
        {"rateLimits":{"credits":{"balance":0,"unlimited":false}}}
        """)
        XCTAssertEqual(AccountQuotaPresentation(snapshot: zero, now: now, isStale: false).creditsText, "0")
    }

    func testTokenCompositionIncludesOutputWithoutChangingInputCacheHitRate() throws {
        var summary = UsageSummary()
        summary.freshInput = 10; summary.output = 20; summary.cacheWrite = 30; summary.cacheRead = 40
        let components = summary.tokenBreakdown
        XCTAssertEqual(components.map { $0.kind.rawValue }, ["freshInput", "output", "cacheWrite", "cacheRead"])
        XCTAssertEqual(components.map(\.tokens), [10, 20, 30, 40])
        XCTAssertEqual(components.reduce(Int64(0)) { $0 + $1.tokens }, summary.realTotalTokens)
        for (component, expected) in zip(components, [0.1, 0.2, 0.3, 0.4]) {
            XCTAssertEqual(try XCTUnwrap(component.fraction), expected, accuracy: 0.0001)
        }
        XCTAssertEqual(summary.cacheHitRate, 40.0 / 80.0, accuracy: 0.0001)
    }

    func testZeroTotalHasNoFractionsWhileCacheOnlyUsageHasFullShare() throws {
        let empty = UsageSummary().tokenBreakdown
        XCTAssertEqual(empty.count, 4)
        XCTAssertTrue(empty.allSatisfy { $0.tokens == 0 && $0.fraction == nil })
        var summary = UsageSummary(); summary.cacheRead = 100
        let components = summary.tokenBreakdown
        let cache = try XCTUnwrap(components.first { $0.kind.rawValue == "cacheRead" })
        XCTAssertEqual(try XCTUnwrap(cache.fraction), 1, accuracy: 0.0001)
        XCTAssertEqual(summary.cacheHitRate, 1, accuracy: 0.0001)
        XCTAssertTrue(components.filter { $0.kind.rawValue != "cacheRead" }.allSatisfy { $0.fraction == 0 })
    }

    func testRangeValidationRejectsReversedAndPreEpochDatesButAllowsEquality() {
        XCTAssertNotNil(UsageRange.validationMessage(start: now, end: now.addingTimeInterval(-1)))
        XCTAssertNotNil(UsageRange.validationMessage(start: Date(timeIntervalSince1970: -1), end: now))
        XCTAssertNil(UsageRange.validationMessage(start: now, end: now))
        XCTAssertNil(UsageRange.validationMessage(start: Date(timeIntervalSince1970: 0), end: now))
    }

    func testPanelHeightUsesAvailableSpaceWithMarginAndPreferredMaximum() {
        XCTAssertEqual(PanelLayout.height(availableHeight: 600), 568)
        XCTAssertEqual(PanelLayout.height(availableHeight: 900), 660)
        for available in [200.0, 400.0, 500.0] {
            let height = PanelLayout.height(availableHeight: available)
            XCTAssertGreaterThan(height, 0)
            XCTAssertLessThanOrEqual(height, available)
        }
    }
}
