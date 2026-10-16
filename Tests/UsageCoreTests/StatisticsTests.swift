import XCTest
import CSQLite
@testable import UsageCore

final class StatisticsTests: XCTestCase {
    private var directory: URL!
    private var path: String!
    private var db: OpaquePointer?
    private var calendar: Calendar!
    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        path = directory.appendingPathComponent("cc-switch.db").path
        XCTAssertEqual(sqlite3_open(path, &db), SQLITE_OK)
        calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        try execute("""
            CREATE TABLE proxy_request_logs (
                request_id TEXT PRIMARY KEY, app_type TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER,
                cache_read_tokens INTEGER, cache_creation_tokens INTEGER, total_cost_usd TEXT, status_code INTEGER,
                created_at INTEGER, data_source TEXT, input_token_semantics INTEGER);
            CREATE TABLE usage_daily_rollups (
                date TEXT, app_type TEXT, request_count INTEGER, input_tokens INTEGER, output_tokens INTEGER,
                cache_read_tokens INTEGER, cache_creation_tokens INTEGER, total_cost_usd TEXT, input_token_semantics INTEGER);
            CREATE TABLE session_log_sync (file_path TEXT PRIMARY KEY, last_synced_at INTEGER);
            """)
    }
    override func tearDownWithError() throws {
        sqlite3_close(db); db = nil
        try FileManager.default.removeItem(at: directory)
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw UsageError.message(String(cString: sqlite3_errmsg(db)))
        }
    }
    private func log(_ id: String, input: Int = 100, output: Int = 10, hit: Int = 80, write: Int = 0,
                     cost: String = "0.123456", semantic: Int = 1, time: Int = 1000,
                     source: String = "codex_session", status: Int = 200, model: String = "test-model", app: String = "codex") throws {
        try execute("INSERT INTO proxy_request_logs VALUES ('\(id)','\(app)','\(model)',\(input),\(output),\(hit),\(write),'\(cost)',\(status),\(time),'\(source)',\(semantic))")
    }
    private func read(_ start: Double = 0, _ end: Double = 10000) throws -> UsageSummary {
        try StatisticsReader(path: path).read(range: UsageRange(start: Date(timeIntervalSince1970: start), end: Date(timeIntervalSince1970: end)), calendar: calendar)
    }
    func testInclusiveTokensAreNotDoubleCountedAndCostsAreNotRepriced() throws {
        try log("a", write: 10, cost: "99.876543")
        let result = try read()
        XCTAssertEqual(result.totalRequests, 1); XCTAssertEqual(result.freshInput, 10)
        XCTAssertEqual(result.realTotalTokens, 110)
        XCTAssertEqual(result.cacheHitRate, 0.8, accuracy: 1e-12)
        XCTAssertEqual(result.totalCost, 99.876543, accuracy: 1e-9)
    }
    func testMixedLegacyTotalAndFreshSemantics() throws {
        try log("total", write: 10, semantic: 1)
        try log("legacy", write: 10, semantic: 0)
        try log("fresh", input: 20, write: 10, semantic: 2)
        let result = try read()
        XCTAssertEqual(result.freshInput, 50); XCTAssertEqual(result.realTotalTokens, 350)
        XCTAssertEqual(result.cacheHitRate, 240.0 / 320, accuracy: 1e-12)
    }
    func testInputSmallerThanCacheUsesCCSwitchFallback() throws {
        try log("anomalous", input: 20, hit: 80, write: 10)
        XCTAssertEqual(try read().freshInput, 20)
    }
    func testProxyAndSessionDeduplication() throws {
        try log("proxy", cost: "2", source: "proxy")
        try log("session", cost: "5", time: 1100)
        let result = try read()
        XCTAssertEqual(result.totalRequests, 1); XCTAssertEqual(result.totalCost, 2)
    }
    func testDedupUsesProxyOutsideSelectedRange() throws {
        try log("proxy", time: 950, source: "proxy")
        try log("session", time: 1050)
        XCTAssertEqual(try read(1000, 1100).totalRequests, 0)
    }
    func testFailedProxyDoesNotHideSession() throws {
        try log("proxy", source: "proxy", status: 500)
        try log("session")
        XCTAssertEqual(try read().totalRequests, 2)
    }
    func testOutsideDedupWindowAndOtherModelsRemain() throws {
        try log("proxy", source: "proxy")
        try log("late", time: 1601)
        try log("different", model: "different-model")
        XCTAssertEqual(try read().totalRequests, 3)
    }
    func testLegacyProxyMissingCacheWriteStillDeduplicates() throws {
        try log("proxy", semantic: 0, source: "proxy")
        try log("session", write: 10)
        XCTAssertEqual(try read().totalRequests, 1)
    }
    func testNullSourceIsProxyAndUnknownModelMatches() throws {
        try log("proxy", source: "proxy", model: "unknown")
        try execute("UPDATE proxy_request_logs SET data_source=NULL WHERE request_id='proxy'")
        try log("session")
        XCTAssertEqual(try read().totalRequests, 1)
    }
    func testOtherAppsAreExcluded() throws {
        try log("codex")
        try log("claude", app: "claude")
        XCTAssertEqual(try read().totalRequests, 1)
    }
    func testFullDayRollupsMergeWithDetails() throws {
        try execute("INSERT INTO usage_daily_rollups VALUES ('1970-01-01','codex',4,20,10,80,0,'7.25',2)")
        try log("new", cost: "2.75", time: 90000)
        let result = try read(0, 100000)
        XCTAssertEqual(result.totalRequests, 5); XCTAssertEqual(result.totalCost, 10)
        XCTAssertEqual(result.realTotalTokens, 220)
        XCTAssertFalse(result.archiveBoundaryOmitted)
    }
    func testPartialArchivedBoundaryIsOmittedAndFlagged() throws {
        try execute("INSERT INTO usage_daily_rollups VALUES ('1970-01-01','codex',4,20,10,80,0,'7.25',2)")
        let result = try read(3600, 100000)
        XCTAssertEqual(result.totalRequests, 0); XCTAssertTrue(result.archiveBoundaryOmitted)
    }
    func testEmptyDatabase() throws {
        let result = try read()
        XCTAssertEqual(result.totalRequests, 0); XCTAssertEqual(result.realTotalTokens, 0)
        XCTAssertEqual(result.cacheHitRate, 0); XCTAssertNil(result.latestRecordAt)
    }
    func testReadsCommittedWALChangesWithoutChangingData() throws {
        try execute("PRAGMA journal_mode=WAL")
        try log("a")
        XCTAssertEqual(try read().totalRequests, 1)
        try log("b")
        XCTAssertEqual(try read().totalRequests, 2)
        let before = try Data(contentsOf: URL(fileURLWithPath: path))
        _ = try read()
        XCTAssertEqual(before, try Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertEqual(sqlite3_total_changes(db), 2)
    }
    func testTodayRolloverReadsNewlySyncedRecordsWithoutKeepingYesterday() throws {
        var local = Calendar(identifier: .gregorian); local.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let before = ISO8601DateFormatter().date(from: "2026-10-15T23:59:59+08:00")!
        let after = before.addingTimeInterval(60)
        try execute("PRAGMA journal_mode=WAL")
        try log("yesterday", cost: "99.75", time: Int(before.timeIntervalSince1970))
        let reader = StatisticsReader(path: path)
        let previous = try reader.read(range: RangePreset.today.resolve(now: before, calendar: local), calendar: local)
        XCTAssertEqual(previous.totalRequests, 1)
        let todayRange = try RangePreset.today.resolve(now: after, calendar: local)
        XCTAssertEqual(try reader.read(range: todayRange, calendar: local).totalRequests, 0)
        try log("today", cost: "3.25", time: Int(after.timeIntervalSince1970)-1)
        let current = try reader.read(range: todayRange, calendar: local)
        XCTAssertEqual(current.totalRequests, 1)
        XCTAssertEqual(current.totalCost, 3.25, accuracy: 1e-9)
        XCTAssertEqual(current.queriedRange, todayRange)
        XCTAssertTrue(RangePreset.today.needsDayRolloverRefresh(queriedRange: previous.queriedRange!, now: after, calendar: local))
    }
    func testMissingDatabaseIsNotCreated() {
        let missing = directory.appendingPathComponent("missing.db").path
        XCTAssertThrowsError(try StatisticsReader(path: missing).read(range: UsageRange(start: Date(timeIntervalSince1970: 0), end: Date())))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing))
    }
    func testIncompatibleSchemaFailsInsteadOfShowingZero() throws {
        try execute("ALTER TABLE proxy_request_logs RENAME TO old_logs; CREATE TABLE proxy_request_logs (request_id TEXT)")
        XCTAssertThrowsError(try read())
    }
    func testDatabaseWithoutOptionalSemanticsColumnUsesLegacy() throws {
        try log("legacy")
        try execute("ALTER TABLE proxy_request_logs DROP COLUMN input_token_semantics")
        XCTAssertEqual(try read().freshInput, 20)
    }
}
