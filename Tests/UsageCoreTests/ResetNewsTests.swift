import XCTest
@testable import UsageCore

enum NewsFixture {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static func data(id: String = "one", status: String = "announced", post: String = "post-one",
                     presentationStatus: String = "announced", basis: String? = nil) throws -> Data {
        var event: [String: Any] = [
            "id": id, "type": "direct_reset", "label": "全员重置", "title": "额度重置消息",
            "status": status, "createdAt": "2026-10-15T12:00:00.000+08:00", "updatedAt": "2026-10-15T13:00:00+08:00",
            "scope": "所有用户", "presentation": ["status": presentationStatus, "scopeKnown": false, "kindExplicit": false],
            "estimate": ["from": "2026-10-15T12:00:00+08:00", "through": "2026-10-15T13:00:00+08:00", "label": "预计中午"],
            "posts": [["id": post, "publishedAt": "2026-10-15T12:00:00+08:00", "stage": "预告", "url": "https://x.com/thsottiaux/status/1"]],
            "url": "https://aihot.news/codex-reset"
        ]
        if let basis { event["confirmationBasis"] = basis; event["confirmedAt"] = "2026-10-15T14:00:00+08:00" }
        return try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1, "timezone": "Asia/Shanghai", "checkedAt": "2026-10-15T20:00:00+08:00",
            "historyFrom": "2026-10-08T00:00:00+08:00", "events": [event], "activities": []
        ])
    }
    static func feed(id: String = "one", status: String = "announced", post: String = "post-one",
                     presentationStatus: String = "announced", basis: String? = nil) throws -> ResetNewsFeed {
        try ResetNewsFeed.decode(data(id: id, status: status, post: post, presentationStatus: presentationStatus, basis: basis))
    }
}

final class ResetNewsTests: XCTestCase {
    func testFirstSuccessfulFetchIsBaselineNotUnreadHistory() throws {
        var inbox = ResetNewsInbox(); inbox.receive(try NewsFixture.feed(), etag: "v1")
        XCTAssertTrue(inbox.initialized); XCTAssertTrue(inbox.unreadIDs.isEmpty)
    }
    func testNewEventIsUnreadAndSnapshotReplacesOldData() throws {
        var inbox = ResetNewsInbox(); inbox.receive(try NewsFixture.feed(), etag: "v1")
        inbox.receive(try NewsFixture.feed(id: "two"), etag: "v2")
        XCTAssertEqual(inbox.unreadIDs, ["event:two"])
        XCTAssertEqual(inbox.feed?.events.map(\.id), ["two"])
    }
    func testAnnouncementBecomingConfirmedIsNewUpdate() throws {
        var inbox = ResetNewsInbox(); inbox.receive(try NewsFixture.feed(), etag: nil)
        inbox.receive(try NewsFixture.feed(status: "confirmed", basis: "source_post"), etag: nil)
        XCTAssertEqual(inbox.unreadIDs, ["event:one"])
    }
    func testNewSourcePostAlertsEvenIfUpdatedAtDoesNotAdvance() throws {
        var inbox = ResetNewsInbox(); inbox.receive(try NewsFixture.feed(), etag: nil)
        inbox.receive(try NewsFixture.feed(post: "new-confirmation-post"), etag: nil)
        XCTAssertEqual(inbox.unreadIDs.count, 1)
    }
    func testScanTimeEstimateAndDerivedStatusChangesDoNotRealert() throws {
        var inbox = ResetNewsInbox(); let original = try NewsFixture.feed()
        inbox.receive(original, etag: nil)
        var changed = original
        changed.checkedAt = Date(); changed.events[0].updatedAt = Date()
        changed.events[0].presentation?.status = "likely_completed"
        changed.events[0].estimate?.through = Date()
        inbox.receive(changed, etag: "different-etag")
        XCTAssertTrue(inbox.unreadIDs.isEmpty)
    }
    func testReadThenUnchangedFetchStaysRead() throws {
        var inbox = ResetNewsInbox(); inbox.receive(try NewsFixture.feed(), etag: nil)
        let next = try NewsFixture.feed(id: "two")
        inbox.receive(next, etag: nil); inbox.markRead(); inbox.receive(next, etag: nil)
        XCTAssertTrue(inbox.unreadIDs.isEmpty)
    }
    func testExpiredSourcePostsLeavingRecentWindowDoNotRealert() throws {
        var inbox = ResetNewsInbox(); var feed = try NewsFixture.feed()
        inbox.receive(feed, etag: nil); feed.events[0].posts = []
        inbox.receive(feed, etag: nil)
        XCTAssertTrue(inbox.unreadIDs.isEmpty)
    }
    func testRemovedEventsDoNotLeavePhantomBadge() throws {
        var inbox = ResetNewsInbox(); inbox.receive(try NewsFixture.feed(), etag: nil)
        var next = try NewsFixture.feed(id: "two")
        inbox.receive(next, etag: nil); next.events = []; inbox.receive(next, etag: nil)
        XCTAssertTrue(inbox.unreadIDs.isEmpty)
    }
    func testExplicitWithdrawalIsUnreadButRelatedSocialPostIsNot() throws {
        var inbox = ResetNewsInbox(); var feed = try NewsFixture.feed()
        inbox.receive(feed, etag: nil)
        let json = """
        {"id":"withdrawal","publishedAt":"2026-10-15T15:00:00+08:00","eventIds":["one"],"kind":"event_update","statusChanged":true,"action":"withdraw","url":"https://x.com/thsottiaux/status/2"}
        """
        var activity = try ResetNewsSource.decoder().decode(ResetNewsActivity.self, from: Data(json.utf8))
        feed.events = []; activity.kind = "related"; feed.activities = [activity]
        inbox.receive(feed, etag: nil); XCTAssertTrue(inbox.unreadIDs.isEmpty)
        activity.kind = "event_update"; feed.activities = [activity]
        inbox.receive(feed, etag: nil); XCTAssertEqual(inbox.unreadIDs, ["withdraw:withdrawal"])
    }
    func testEmptyInitialBaselineStillDetectsFirstFutureEvent() throws {
        var inbox = ResetNewsInbox(); var empty = try NewsFixture.feed(); empty.events = []
        inbox.receive(empty, etag: nil); inbox.receive(try NewsFixture.feed(), etag: nil)
        XCTAssertEqual(inbox.unreadIDs.count, 1)
    }
    func testLegacyAllUsersLabelAndUnspecifiedScopeAreNotPresentedAsUniversal() throws {
        let event = try XCTUnwrap(NewsFixture.feed().events.first)
        XCTAssertEqual(event.kindText, "重置（形式未明确）")
        XCTAssertEqual(event.scopeText, "原帖未说明适用人群")
    }
    func testEstimatedWindowNeverConfirmsArrival() throws {
        let event = try XCTUnwrap(NewsFixture.feed(presentationStatus: "likely_completed").events.first)
        XCTAssertFalse(event.isConfirmed); XCTAssertTrue(event.statusText.contains("未确认"))
        XCTAssertTrue(event.estimateText?.contains("AIHOT 预计") == true)
    }
    func testReceiptReviewIsDistinctFromTiboConfirmationAndHidesOldEstimate() throws {
        let event = try XCTUnwrap(NewsFixture.feed(status: "confirmed", basis: "receipt_review").events.first)
        XCTAssertEqual(event.statusText, "到账核实"); XCTAssertTrue(event.timeText.hasPrefix("核实记录"))
        XCTAssertNil(event.estimateText)
    }
    func testBadgeToggleAndMonitoringToggleOnlyControlVisibility() throws {
        var inbox = ResetNewsInbox(); var empty = try NewsFixture.feed(); empty.events = []
        inbox.receive(empty, etag: nil); inbox.receive(try NewsFixture.feed(), etag: nil)
        XCTAssertTrue(inbox.shouldShowIndicator(enabled: true, monitoring: true))
        XCTAssertFalse(inbox.shouldShowIndicator(enabled: false, monitoring: true))
        XCTAssertFalse(inbox.shouldShowIndicator(enabled: true, monitoring: false))
        XCTAssertEqual(inbox.unreadIDs.count, 1)
    }
    func testCooldownAndRetryAfterSurvivePersistence() throws {
        let suite = "CodexUsageNewsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var inbox = ResetNewsInbox(); inbox.receive(try NewsFixture.feed(), etag: "etag-one", at: NewsFixture.now)
        inbox.receive(try NewsFixture.feed(id: "two"), etag: "etag-two", at: NewsFixture.now)
        inbox.beginAttempt(at: NewsFixture.now)
        XCTAssertFalse(inbox.canFetch(at: NewsFixture.now.addingTimeInterval(599)))
        XCTAssertTrue(inbox.canFetch(at: NewsFixture.now.addingTimeInterval(600)))
        inbox.recordFailure("稍后重试", retryAt: NewsFixture.now.addingTimeInterval(1800)); inbox.save(to: defaults)
        let loaded = ResetNewsInbox.load(from: defaults)
        XCTAssertEqual(loaded.unreadIDs, ["event:two"]); XCTAssertEqual(loaded.etag, "etag-two")
        XCTAssertFalse(loaded.canFetch(at: NewsFixture.now.addingTimeInterval(1200)))
        XCTAssertEqual(loaded.feed?.events.first?.id, "two")
    }
    func test304PreservesUnreadAndCachedContent() throws {
        var inbox = ResetNewsInbox(); var empty = try NewsFixture.feed(); empty.events = []
        inbox.receive(empty, etag: nil); inbox.receive(try NewsFixture.feed(), etag: "etag")
        try inbox.recordNotModified(at: NewsFixture.now)
        XCTAssertEqual(inbox.unreadIDs, ["event:one"]); XCTAssertEqual(inbox.feed?.events.count, 1)
        XCTAssertEqual(inbox.receivedAt, NewsFixture.now)
    }
    func test304WithoutCacheFails() { var inbox = ResetNewsInbox(); XCTAssertThrowsError(try inbox.recordNotModified()) }
    func testOnlyExpectedHTTPSLinksAreAllowed() {
        XCTAssertNotNil(ResetNewsSource.safeURL("https://x.com/thsottiaux/status/1"))
        for value in ["javascript:alert(1)", "file:///etc/passwd", "https://x.com.evil.test/1", "https://name:secret@x.com/1", "http://aihot.news/"] {
            XCTAssertNil(ResetNewsSource.safeURL(value))
        }
    }
    func testUnsupportedSchemaFailsExplicitly() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NewsFixture.data()) as? [String: Any])
        json["schemaVersion"] = 2
        XCTAssertThrowsError(try ResetNewsFeed.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testDuplicateEventIDsFailInsteadOfCrashingOnMerge() throws {
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: NewsFixture.data()) as? [String: Any])
        let events = try XCTUnwrap(json["events"] as? [[String: Any]])
        json["events"] = events + events
        XCTAssertThrowsError(try ResetNewsFeed.decode(JSONSerialization.data(withJSONObject: json)))
    }
    func testOldSettingsGetNewsDefaultsAndShortIntervalsAreClamped() throws {
        let suite = "CodexUsageNewsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data(#"{"menuMetrics":["cost"],"resetNewsInterval":1}"#.utf8), forKey: "appSettings")
        let settings = AppSettings.load(from: defaults)
        XCTAssertTrue(settings.resetNewsEnabled); XCTAssertTrue(settings.showResetNewsIndicator)
        XCTAssertEqual(settings.menuMetrics, [.cost]); XCTAssertEqual(settings.resetNewsInterval, 600)
    }
}
