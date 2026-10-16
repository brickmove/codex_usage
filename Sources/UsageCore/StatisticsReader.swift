import Foundation
import CSQLite

/// Reads CC Switch's persisted amounts. It never imports sessions or computes prices.
public struct StatisticsReader: Sendable {
    public let path: String
    public let codexHome: String
    public init(path: String = "~/.cc-switch/cc-switch.db", codexHome: String = "") {
        self.path = path; self.codexHome = codexHome
    }

    public func read(range: UsageRange, calendar: Calendar = .current) throws -> UsageSummary {
        let db = try ReadOnlyDatabase(path: AppSettings.expandedPath(path))
        try db.execute("BEGIN")
        defer { try? db.execute("ROLLBACK") }
        let fields = try db.columns("proxy_request_logs")
        let required: Set<String> = ["app_type", "model", "input_tokens", "output_tokens", "cache_read_tokens",
            "cache_creation_tokens", "total_cost_usd", "status_code", "created_at"]
        guard required.isSubset(of: fields) else {
            throw UsageError.message("CC Switch 数据库结构不兼容，缺少字段：" + required.subtracting(fields).sorted().joined(separator: ", "))
        }
        let hasSource = fields.contains("data_source")
        let semantics = fields.contains("input_token_semantics")
        let lower = range.startSeconds - 600, upper = range.endSeconds + 600
        var dedup = "1 = 1"
        var parameters: [SQLValue] = [.integer(range.startSeconds), .integer(range.endSeconds)]
        if hasSource {
            let proxies = try db.query("""
                SELECT COUNT(*) AS count FROM proxy_request_logs
                WHERE app_type = 'codex' AND COALESCE(data_source, 'proxy') = 'proxy'
                AND status_code >= 200 AND status_code < 300 AND created_at BETWEEN ?1 AND ?2
                """, [.integer(lower), .integer(upper)]).first?.int("count") ?? 0
            if proxies > 0 {
                // Same effective-record rules as CC Switch, restricted to Codex.
                // Starting with proxy rows avoids a correlated scan for every imported event.
                let legacy = semantics ? "p.input_token_semantics = 0" : "1 = 1"
                dedup = """
                    l.rowid NOT IN (
                        SELECT s.rowid FROM proxy_request_logs p JOIN proxy_request_logs s
                        ON s.app_type = p.app_type
                        AND COALESCE(s.data_source, 'proxy') IN ('session_log','codex_session','gemini_session','opencode_session')
                        AND s.input_tokens = p.input_tokens AND s.output_tokens = p.output_tokens
                        AND s.cache_read_tokens = p.cache_read_tokens
                        AND s.created_at BETWEEN p.created_at - 600 AND p.created_at + 600
                        AND (s.cache_creation_tokens = p.cache_creation_tokens
                             OR (s.cache_creation_tokens = 0 AND s.data_source IN ('codex_session','gemini_session','opencode_session'))
                             OR (p.cache_creation_tokens = 0 AND \(legacy) AND s.data_source = 'codex_session'))
                        AND (LOWER(s.model) = LOWER(p.model) OR LOWER(s.model) = 'unknown' OR LOWER(p.model) = 'unknown')
                        WHERE p.app_type = 'codex' AND COALESCE(p.data_source, 'proxy') = 'proxy'
                        AND p.status_code >= 200 AND p.status_code < 300
                        AND p.created_at BETWEEN ?3 AND ?4
                    )
                    """
                parameters += [.integer(lower), .integer(upper)]
            }
        }
        var summary = UsageSummary()
        summary.queriedRange = range
        let detail = try db.query("""
            SELECT COUNT(*) AS requests, COALESCE(SUM(CAST(l.total_cost_usd AS REAL)),0) AS cost,
                   COALESCE(SUM(\(freshInput(alias: "l", hasSemantics: semantics))),0) AS fresh,
                   COALESCE(SUM(l.output_tokens),0) AS output,
                   COALESCE(SUM(l.cache_creation_tokens),0) AS write,
                   COALESCE(SUM(l.cache_read_tokens),0) AS hit
            FROM proxy_request_logs l
            WHERE l.app_type = 'codex' AND l.created_at BETWEEN ?1 AND ?2 AND \(dedup)
            """, parameters)
        if let row = detail.first { merge(row, into: &summary) }

        let rollupFields = try db.columns("usage_daily_rollups")
        if !rollupFields.isEmpty {
            let rollupRequired: Set<String> = ["date", "app_type", "request_count", "total_cost_usd", "input_tokens",
                "output_tokens", "cache_creation_tokens", "cache_read_tokens"]
            guard rollupRequired.isSubset(of: rollupFields) else {
                throw UsageError.message("CC Switch 历史汇总结构不兼容，请更新工具。")
            }
            if let (first, last) = range.rollupBounds(calendar: calendar) {
                let rows = try db.query("""
                    SELECT COALESCE(SUM(r.request_count),0) AS requests,
                           COALESCE(SUM(CAST(r.total_cost_usd AS REAL)),0) AS cost,
                           COALESCE(SUM(\(freshInput(alias: "r", hasSemantics: rollupFields.contains("input_token_semantics")))),0) AS fresh,
                           COALESCE(SUM(r.output_tokens),0) AS output,
                           COALESCE(SUM(r.cache_creation_tokens),0) AS write,
                           COALESCE(SUM(r.cache_read_tokens),0) AS hit
                    FROM usage_daily_rollups r WHERE r.app_type = 'codex' AND r.date BETWEEN ?1 AND ?2
                    """, [.text(first), .text(last)])
                if let row = rows.first { merge(row, into: &summary) }
            }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar; formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
            let bounds = range.rollupBounds(calendar: calendar)
            let boundaryDays = Set([formatter.string(from: range.start), formatter.string(from: range.end)])
            for day in boundaryDays where bounds == nil || day < bounds!.0 || day > bounds!.1 {
                let count = try db.query("SELECT COUNT(*) AS count FROM usage_daily_rollups WHERE app_type='codex' AND date=?1", [.text(day)])
                if (count.first?.int("count") ?? 0) > 0 { summary.archiveBoundaryOmitted = true }
            }
        }
        if let latest = try db.query("SELECT MAX(created_at) AS latest FROM proxy_request_logs WHERE app_type='codex'").first?.optionalDouble("latest") {
            summary.latestRecordAt = Date(timeIntervalSince1970: latest)
        }
        let syncFields = try db.columns("session_log_sync")
        if syncFields.contains("file_path") && syncFields.contains("last_synced_at") {
            let home = codexHome.isEmpty
                ? (ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "~/.codex") : codexHome
            let prefix = AppSettings.expandedPath(home).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            // instr uses a bound literal prefix, so '%' and '_' in paths are not wildcard patterns.
            let filePrefix = "/" + prefix + "/"
            let synced = try db.query("SELECT MAX(last_synced_at) AS latest FROM session_log_sync WHERE instr(file_path,?1)=1", [.text(filePrefix)])
                .first?.optionalDouble("latest")
            if let synced, synced > 0 && synced < 1e11 { summary.lastSyncedAt = Date(timeIntervalSince1970: synced) }
        }
        summary.readAt = Date()
        return summary
    }

    private func merge(_ row: SQLRow, into s: inout UsageSummary) {
        s.totalRequests += row.int("requests"); s.totalCost += row.double("cost")
        s.freshInput += row.int("fresh"); s.output += row.int("output")
        s.cacheWrite += row.int("write"); s.cacheRead += row.int("hit")
    }

    private func freshInput(alias: String, hasSemantics: Bool) -> String {
        let a = alias + ".", semantic = hasSemantics ? a + "input_token_semantics" : "0"
        // Codex input includes cache for TOTAL rows. LEGACY subtracts only cache reads.
        return """
            CASE WHEN \(semantic) = 2 THEN \(a)input_tokens
                 WHEN \(semantic) = 1 AND \(a)input_tokens >= \(a)cache_read_tokens + \(a)cache_creation_tokens
                 THEN \(a)input_tokens - \(a)cache_read_tokens - \(a)cache_creation_tokens
                 WHEN \(semantic) = 0 AND \(a)input_tokens >= \(a)cache_read_tokens
                 THEN \(a)input_tokens - \(a)cache_read_tokens
                 ELSE \(a)input_tokens END
            """
    }
}

private enum SQLValue { case integer(Int64), text(String), real(Double), null }
private struct SQLRow {
    var fields: [String: SQLValue]
    func int(_ key: String) -> Int64 {
        switch fields[key] { case .integer(let v): return v; case .real(let v): return Int64(v); default: return 0 }
    }
    func double(_ key: String) -> Double { optionalDouble(key) ?? 0 }
    func optionalDouble(_ key: String) -> Double? {
        switch fields[key] { case .integer(let v): return Double(v); case .real(let v): return v; default: return nil }
    }
    func text(_ key: String) -> String? { if case .text(let v) = fields[key] { return v }; return nil }
}

private final class ReadOnlyDatabase {
    private var handle: OpaquePointer?
    init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else {
            throw UsageError.message("未找到 CC Switch 数据库，请在设置中选择 cc-switch.db。")
        }
        let status = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil)
        guard status == SQLITE_OK else {
            let text = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "无法打开数据库"
            sqlite3_close(handle); handle = nil
            throw UsageError.message("读取 CC Switch 数据库失败：\(text)")
        }
        sqlite3_busy_timeout(handle, 1500)
        try execute("PRAGMA query_only=ON")
        guard sqlite3_db_readonly(handle, "main") == 1 else { throw UsageError.message("数据库未以只读方式打开。") }
    }
    deinit { sqlite3_close(handle) }
    func execute(_ sql: String) throws { _ = try query(sql) }
    func columns(_ table: String) throws -> Set<String> {
        // table is always a compile-time internal identifier.
        Set(try query("PRAGMA table_info(\(table))").compactMap { $0.text("name") })
    }
    func query(_ sql: String, _ values: [SQLValue] = []) throws -> [SQLRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1), result: Int32
            switch value {
            case .integer(let n): result = sqlite3_bind_int64(statement, index, n)
            case .real(let n): result = sqlite3_bind_double(statement, index, n)
            case .text(let s): result = sqlite3_bind_text(statement, index, s, -1, transient)
            case .null: result = sqlite3_bind_null(statement, index)
            }
            guard result == SQLITE_OK else { throw error() }
        }
        var rows: [SQLRow] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return rows }
            guard status == SQLITE_ROW else { throw error() }
            var fields: [String: SQLValue] = [:]
            for i in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, i))
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: fields[name] = .integer(sqlite3_column_int64(statement, i))
                case SQLITE_FLOAT: fields[name] = .real(sqlite3_column_double(statement, i))
                case SQLITE_TEXT: fields[name] = .text(String(cString: sqlite3_column_text(statement, i)))
                default: fields[name] = .null
                }
            }
            rows.append(SQLRow(fields: fields))
        }
    }
    private func error() -> UsageError {
        .message("读取 CC Switch 数据库失败：" + String(cString: sqlite3_errmsg(handle)))
    }
}
