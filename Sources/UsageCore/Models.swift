import Foundation

public enum UsageError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}

public enum RangePreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case today, last24Hours, week, month, all, custom
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .today: return "今日"
        case .last24Hours: return "最近 24 小时"
        case .week: return "最近 7 天"
        case .month: return "最近 30 天"
        case .all: return "全部时间"
        case .custom: return "自定义时段"
        }
    }
    public func needsDayRolloverRefresh(queriedRange: UsageRange, now: Date,
                                        calendar: Calendar = .current) -> Bool {
        switch self {
        case .today, .week, .month:
            return (try? resolve(now: now, calendar: calendar).start) != queriedRange.start
        default: return false
        }
    }
    public func resolve(now: Date = Date(), start: Date? = nil, end: Date? = nil,
                        calendar: Calendar = .current) throws -> UsageRange {
        let midnight = calendar.startOfDay(for: now)
        switch self {
        case .today: return try UsageRange(start: midnight, end: now)
        case .last24Hours: return try UsageRange(start: now.addingTimeInterval(-86400), end: now)
        case .week, .month:
            let days = self == .week ? 6 : 29
            return try UsageRange(start: calendar.date(byAdding: .day, value: -days, to: midnight)!, end: now)
        case .all: return try UsageRange(start: Date(timeIntervalSince1970: 0), end: now)
        case .custom:
            guard let start, let end else { throw UsageError.message("请选择开始和结束时间。") }
            return try UsageRange(start: start, end: end)
        }
    }
}

public struct UsageRange: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public init(start: Date, end: Date) throws {
        guard start <= end else { throw UsageError.message("开始时间不能晚于结束时间。") }
        guard start.timeIntervalSince1970 >= 0 else { throw UsageError.message("开始时间不能早于 1970 年。") }
        self.start = start; self.end = end
    }
    public var startSeconds: Int64 { Int64(start.timeIntervalSince1970.rounded(.down)) }
    public var endSeconds: Int64 { Int64(end.timeIntervalSince1970.rounded(.down)) }

    /// Matches CC Switch: include only covered local dates; 23:59 is treated as day end.
    public func rollupBounds(calendar: Calendar = .current) -> (String, String)? {
        var first = calendar.startOfDay(for: start)
        if startSeconds != Int64(first.timeIntervalSince1970) {
            first = calendar.date(byAdding: .day, value: 1, to: first)!
        }
        let parts = calendar.dateComponents([.hour, .minute], from: end)
        var last = calendar.startOfDay(for: end)
        if parts.hour != 23 || parts.minute != 59 {
            last = calendar.date(byAdding: .day, value: -1, to: last)!
        }
        guard first <= last else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: first), formatter.string(from: last))
    }
}

public struct UsageSummary: Codable, Sendable {
    public var totalRequests: Int64 = 0
    public var totalCost: Double = 0
    public var freshInput: Int64 = 0
    public var output: Int64 = 0
    public var cacheWrite: Int64 = 0
    public var cacheRead: Int64 = 0
    public var archiveBoundaryOmitted = false
    public var latestRecordAt: Date?
    public var lastSyncedAt: Date?
    public var readAt: Date = Date()
    public var queriedRange: UsageRange?
    public var realTotalTokens: Int64 { freshInput + output + cacheWrite + cacheRead }
    public var cacheHitRate: Double {
        let denominator = freshInput + cacheWrite + cacheRead
        return denominator > 0 ? Double(cacheRead) / Double(denominator) : 0
    }
    public init() {}
}

public struct RateWindow: Codable, Sendable, Equatable {
    public var usedPercent: Double
    public var windowDurationMins: Int?
    public var resetsAt: Double?
    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
    public var title: String {
        guard let minutes = windowDurationMins else { return "额度窗口" }
        if minutes == 10080 { return "每周额度" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
    public init(usedPercent: Double, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent; self.windowDurationMins = windowDurationMins; self.resetsAt = resetsAt
    }
}

public struct CreditBalance: Decodable, Sendable {
    public var hasCredits: Bool?
    public var unlimited: Bool?
    public var balance: Double?
    enum CodingKeys: String, CodingKey { case hasCredits, unlimited, balance }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasCredits = try c.decodeIfPresent(Bool.self, forKey: .hasCredits)
        unlimited = try c.decodeIfPresent(Bool.self, forKey: .unlimited)
        if let s = try? c.decode(String.self, forKey: .balance) { balance = Double(s) }
        else { balance = try? c.decode(Double.self, forKey: .balance) }
        if let n = balance, !n.isFinite || n < 0 { balance = nil }
    }
}

public struct LimitBucket: Decodable, Sendable {
    public var primary: RateWindow?
    public var secondary: RateWindow?
    public var credits: CreditBalance?
    public var planType: String?
}

public struct ResetCredit: Decodable, Sendable {
    public var status: String?
    public var expiresAt: Double?
}

public struct ResetSummary: Decodable, Sendable {
    public var availableCount: Int
    public var credits: [ResetCredit]?
    public func nextExpiry(now: Date = Date()) -> Date? {
        credits?.filter { $0.status == "available" }
            .compactMap(\.expiresAt).filter { $0 > now.timeIntervalSince1970 }
            .min().map(Date.init(timeIntervalSince1970:))
    }
}

public struct RateLimitsResponse: Decodable, Sendable {
    public var rateLimits: LimitBucket?
    public var rateLimitsByLimitId: [String: LimitBucket]?
    public var rateLimitResetCredits: ResetSummary?
    public var accountId: String?
    public var ordinaryUsageAllowed: Bool?
    public var bucket: LimitBucket? { rateLimitsByLimitId?["codex"] ?? rateLimits }
}

public struct QuotaSnapshot: Sendable {
    public var response: RateLimitsResponse
    public var email: String?
    public var queriedAt: Date
    public var account: CodexAccount?
    public var windows: [RateWindow] { [response.bucket?.primary, response.bucket?.secondary].compactMap { $0 } }
    public var preferredWindow: RateWindow? { windows.first { $0.windowDurationMins == 10080 } ?? windows.first }
    public init(response: RateLimitsResponse, email: String? = nil, queriedAt: Date = Date(), account: CodexAccount? = nil) {
        self.response = response; self.email = email; self.queriedAt = queriedAt; self.account = account
    }
}

/// Display-only account fields from account/read. Never contains authentication tokens.
public struct CodexAccount: Decodable, Equatable, Sendable {
    public let type: String
    public let email: String?
    public let planType: String?
    public init(type: String, email: String? = nil, planType: String? = nil) {
        self.type = type; self.email = email; self.planType = planType
    }
    public var displayName: String {
        if type == "chatgpt" { return email ?? "ChatGPT 账户（未提供邮箱）" }
        if type == "apiKey" { return "API Key 认证" }
        return "其他认证方式"
    }
}

public enum DisplayFormat {
    public static func compact(_ value: Double) -> String {
        for (scale, suffix) in [(1e9, "B"), (1e6, "M"), (1e3, "K")] where abs(value) >= scale {
            return String(format: "%.2f", value / scale).replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression) + suffix
        }
        return String(format: "%.0f", value)
    }
    public static func number(_ value: Double, digits: Int = 2) -> String {
        let f = NumberFormatter(); f.locale = Locale(identifier: "zh_CN")
        f.numberStyle = .decimal; f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: value)) ?? "—"
    }
    public static func money(_ value: Double) -> String { "$" + String(format: "%.2f", value) }
    public static func countdown(to date: Date?, now: Date = Date(), compact: Bool = false) -> String {
        guard let date else { return "重置时间未知" }
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "等待更新" }
        let days = seconds / 86400, hours = seconds / 3600 % 24, minutes = seconds / 60 % 60
        if compact {
            if days > 0 { return "\(days)d" + (hours > 0 ? "\(hours)h" : "") }
            if hours > 0 { return "\(hours)h" + (minutes > 0 ? "\(minutes)m" : "") }
            return minutes > 0 ? "\(minutes)m" : "<1m"
        }
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
        return minutes > 0 ? "\(minutes) 分钟" : "不到 1 分钟"
    }
}
