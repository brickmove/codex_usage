import XCTest
@testable import UsageCore

final class QuotaAndRangeTests: XCTestCase {
    private func decode(_ json: String) throws -> RateLimitsResponse {
        try JSONDecoder().decode(RateLimitsResponse.self, from: Data(json.utf8))
    }
    func testWeeklyWindowIsSelectedByDurationAndCodexBucketWins() throws {
        let result = try decode("""
        {"rateLimits":{"primary":{"usedPercent":90,"windowDurationMins":300}},
         "rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":10,"windowDurationMins":300},
         "secondary":{"usedPercent":20,"windowDurationMins":10080}},
         "other":{"primary":{"usedPercent":99,"windowDurationMins":10080}}}}
        """)
        XCTAssertEqual(QuotaSnapshot(response: result).preferredWindow?.remainingPercent, 80)
    }
    func testCreditsSupportStringNumericZeroAndUnlimited() throws {
        for value in ["\"62197.23\"", "62197.23", "0"] {
            let q = try decode("{\"rateLimits\":{\"credits\":{\"balance\":\(value),\"hasCredits\":true,\"unlimited\":false}}}")
            XCTAssertNotNil(q.bucket?.credits?.balance)
        }
        let q = try decode("{\"rateLimits\":{\"credits\":{\"unlimited\":true,\"hasCredits\":true}}}")
        XCTAssertEqual(q.bucket?.credits?.unlimited, true)
    }
    func testMissingFieldsRemainUnknown() throws {
        let q = try decode("{\"rateLimits\":{}}")
        XCTAssertNil(q.bucket?.credits); XCTAssertNil(q.rateLimitResetCredits)
        XCTAssertNil(QuotaSnapshot(response: q).preferredWindow)
    }
    func testResetCountIsAuthoritativeWhenDetailsAreCapped() throws {
        let q = try decode("""
        {"rateLimitResetCredits":{"availableCount":5,"credits":[
        {"status":"available","expiresAt":2000},{"status":"redeemed","expiresAt":1500},
        {"status":"available","expiresAt":500}]}}
        """)
        XCTAssertEqual(q.rateLimitResetCredits?.availableCount, 5)
        XCTAssertEqual(q.rateLimitResetCredits?.nextExpiry(now: Date(timeIntervalSince1970: 1000))?.timeIntervalSince1970, 2000)
    }
    func testLocalDayHandlesDSTAndIsNotRolling24Hours() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let now = ISO8601DateFormatter().date(from: "2026-03-08T23:00:00-07:00")!
        let range = try RangePreset.today.resolve(now: now, calendar: c)
        XCTAssertEqual(range.end.timeIntervalSince(range.start), 22 * 3600)
        let week = try RangePreset.week.resolve(now: now, calendar: c)
        XCTAssertEqual(c.component(.hour, from: week.start), 0)
        XCTAssertEqual(c.component(.day, from: week.start), 2)
    }
    func testInvalidRangeFails() {
        XCTAssertThrowsError(try UsageRange(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 99)))
    }
    func testEndMinuteMatchesCCSwitchArchiveBoundary() throws {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!
        let range = try UsageRange(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86340))
        XCTAssertEqual(range.rollupBounds(calendar: c)?.1, "1970-01-01")
    }
    func testCountdownDoesNotInventFutureResetAfterExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(DisplayFormat.countdown(to: Date(timeIntervalSince1970: 900), now: now), "等待更新")
        XCTAssertEqual(DisplayFormat.countdown(to: now.addingTimeInterval(86400+7200), now: now, compact: true), "1d2h")
    }
    func testSettingsPersistWithoutCredentials() throws {
        let suite = "CodexUsageTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = AppSettings(); settings.range = .month; settings.setMenuMetric(.credits, enabled: false)
        settings.save(to: defaults)
        XCTAssertEqual(AppSettings.load(from: defaults), settings)
    }
}
