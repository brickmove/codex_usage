import Foundation
import CryptoKit

public enum ResetNewsSource {
    public static let pageURL = URL(string: "https://aihot.news/codex-reset")!
    public static let feedURL = URL(string: "https://aihot.news/api/v1/codex-resets/recent")!
    public static let minimumInterval: TimeInterval = 600

    public static func safeURL(_ value: String?) -> URL? {
        guard let value, let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), ["aihot.news", "x.com", "www.x.com", "twitter.com", "www.twitter.com"].contains(host),
              url.user == nil, url.password == nil else { return nil }
        return url
    }
    public static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter.string(from: date)
    }
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let text = try value.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: value.codingPath, debugDescription: "Invalid ISO 8601 date"))
        }
        return decoder
    }
}

public struct ResetNewsFeed: Codable, Sendable {
    public var schemaVersion: Int
    public var timezone: String
    public var checkedAt: Date?
    public var historyFrom: Date
    public var events: [ResetNewsEvent]
    public var activities: [ResetNewsActivity]?
    public var monitor: ResetNewsMonitor?

    public static func decode(_ data: Data) throws -> ResetNewsFeed {
        let feed: ResetNewsFeed
        do { feed = try ResetNewsSource.decoder().decode(Self.self, from: data) }
        catch { throw UsageError.message("无法解析 AIHOT 重置动态，请稍后重试或查看来源网页。") }
        guard feed.schemaVersion == 1, feed.timezone == "Asia/Shanghai" else {
            throw UsageError.message("AIHOT 重置接口已变更，请更新应用。")
        }
        guard Set(feed.events.map(\.id)).count == feed.events.count else {
            throw UsageError.message("AIHOT 返回了重复的重置记录，请稍后重试。")
        }
        return feed
    }
    public var sortedEvents: [ResetNewsEvent] { events.sorted { $0.updatedAt > $1.updatedAt } }
    public var withdrawals: [ResetNewsActivity] {
        var seen = Set<String>()
        return (activities ?? []).filter {
            $0.kind == "event_update" && $0.statusChanged && $0.action == "withdraw" && seen.insert($0.id).inserted
        }.sorted { $0.publishedAt > $1.publishedAt }
    }
    public var versions: [String: String] {
        var result = Dictionary(uniqueKeysWithValues: events.map { ($0.noticeID, $0.revision) })
        for withdrawal in withdrawals { result[withdrawal.noticeID] = withdrawal.id }
        return result
    }
}

public struct ResetNewsMonitor: Codable, Sendable {
    public var status: String
    public var lastAttemptAt: Date?
    public var lastCollectedAt: Date?
    public var lastVerifiedAt: Date?
    public var statusText: String {
        switch status {
        case "healthy": return "来源监控正常"
        case "delayed": return "来源检查延迟"
        case "attention": return "来源监控需关注"
        default: return "来源监控状态未知"
        }
    }
}

public struct ResetNewsEvent: Codable, Identifiable, Sendable {
    public struct Presentation: Codable, Sendable {
        public var reportedAt: Date?
        public var status: String?
        public var scopeKnown: Bool?
        public var scopeLabel: String?
        public var kindExplicit: Bool?
        public var timeInferred: Bool?
        public var audienceZh: String?
        public var productsZh: String?
    }
    public struct Window: Codable, Sendable {
        public var from: Date
        public var through: Date
        public var label: String
    }
    public struct Post: Codable, Identifiable, Sendable {
        public var id: String
        public var publishedAt: Date
        public var stage: String
        public var url: String
    }
    public var id: String
    public var type: String
    public var displayLabel: String?
    public var presentation: Presentation?
    public var status: String
    public var title: String
    public var scope: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var confirmedAt: Date?
    public var confirmationBasis: String?
    public var estimate: Window?
    public var schedule: Window?
    public var posts: [Post]
    public var url: String

    public var noticeID: String { "event:" + id }
    public var isConfirmed: Bool { status == "confirmed" }
    public var kindText: String {
        if let displayLabel, !displayLabel.isEmpty { return String(displayLabel.prefix(100)) }
        if type == "reset_credit" { return "重置卡发放" }
        return presentation?.kindExplicit == true ? "额度重置" : "重置（形式未明确）"
    }
    public var scopeText: String {
        if presentation?.scopeKnown == false { return "原帖未说明适用人群" }
        for value in [presentation?.audienceZh, presentation?.scopeLabel, scope] {
            if let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty { return String(text.prefix(200)) }
        }
        return "原帖未说明适用人群"
    }
    public var statusText: String {
        if isConfirmed {
            if confirmationBasis == "source_post" { return "Tibo 已确认" }
            if confirmationBasis == "receipt_review" { return "到账核实" }
            return "已确认"
        }
        switch presentation?.status {
        case "in_progress": return "正在发放，待确认"
        case "expired_unconfirmed": return "预计窗口已过，未确认"
        case "likely_completed": return "可能已生效，未确认"
        default: return "已宣布，等待生效"
        }
    }
    public var timeText: String {
        if isConfirmed {
            guard let confirmedAt else { return "未提供确认时间" }
            return (confirmationBasis == "receipt_review" ? "核实记录 " : "确认帖 ") + ResetNewsSource.dateText(confirmedAt)
        }
        return "公告 " + ResetNewsSource.dateText(presentation?.reportedAt ?? createdAt)
    }
    public var estimateText: String? {
        guard !isConfirmed else { return nil }
        if let estimate { return "AIHOT 预计：" + String(estimate.label.prefix(200)) + "（尚未确认）" }
        if let schedule { return "原帖时间换算：" + String(schedule.label.prefix(200)) }
        return nil
    }

    // Deliberately excludes checkedAt, derived presentation status and moving estimates.
    // The same source update must not re-alert just because a scan or estimated window advances.
    public var revision: String {
        let values: [String: Any] = [
            "type": type, "status": status, "title": title, "displayLabel": displayLabel ?? "",
            "scope": scopeText, "products": presentation?.productsZh ?? "", "kindExplicit": presentation?.kindExplicit ?? false,
            "basis": confirmationBasis ?? "", "confirmedAt": confirmedAt?.timeIntervalSince1970 ?? 0,
            "scheduleFrom": schedule?.from.timeIntervalSince1970 ?? 0,
            "scheduleThrough": schedule?.through.timeIntervalSince1970 ?? 0
        ]
        let data = (try? JSONSerialization.data(withJSONObject: values, options: .sortedKeys)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public struct ResetNewsActivity: Codable, Identifiable, Sendable {
    public var id: String
    public var publishedAt: Date
    public var eventIds: [String]
    public var kind: String
    public var statusChanged: Bool
    public var action: String?
    public var url: String
    public var noticeID: String { "withdraw:" + id }
}

public struct ResetNewsInbox: Codable, Sendable {
    public var feed: ResetNewsFeed?
    public var etag: String?
    public var receivedAt: Date?
    public var lastAttemptAt: Date?
    public var nextAllowedFetchAt: Date?
    public var lastError: String?
    public private(set) var initialized = false
    public private(set) var unreadIDs: Set<String> = []
    private var versions: [String: String] = [:]
    private var sourcePostIDs: [String: Set<String>] = [:]
    public init() {}

    public mutating func receive(_ snapshot: ResetNewsFeed, etag: String?, at date: Date = Date()) {
        let current = snapshot.versions
        let currentPosts = Dictionary(uniqueKeysWithValues: snapshot.events.map { ($0.noticeID, Set($0.posts.map(\.id))) })
        if initialized {
            unreadIDs.formIntersection(Set(current.keys))
            for (key, revision) in current where versions[key] != revision { unreadIDs.insert(key) }
            for (key, ids) in currentPosts where !ids.subtracting(sourcePostIDs[key] ?? []).isEmpty { unreadIDs.insert(key) }
        } else {
            initialized = true
            unreadIDs = []
        }
        versions = current
        sourcePostIDs = currentPosts
        feed = snapshot; self.etag = etag; receivedAt = date; lastError = nil
    }
    public mutating func markRead() { unreadIDs.removeAll() }
    public mutating func beginAttempt(at date: Date = Date()) {
        lastAttemptAt = date
        nextAllowedFetchAt = date.addingTimeInterval(ResetNewsSource.minimumInterval)
    }
    public mutating func recordNotModified(at date: Date = Date()) throws {
        guard feed != nil else { throw UsageError.message("AIHOT 未返回内容，且本机没有缓存，请稍后重试。") }
        receivedAt = date; lastError = nil
    }
    public mutating func recordFailure(_ message: String, retryAt: Date? = nil) {
        lastError = message
        if let retryAt { nextAllowedFetchAt = max(nextAllowedFetchAt ?? .distantPast, retryAt) }
    }
    public func canFetch(at date: Date = Date()) -> Bool { date >= (nextAllowedFetchAt ?? .distantPast) }
    public func shouldShowIndicator(enabled: Bool, monitoring: Bool) -> Bool { enabled && monitoring && !unreadIDs.isEmpty }
    public static func load(from defaults: UserDefaults = AppSettings.preferences) -> Self {
        guard let data = defaults.data(forKey: "resetNewsInbox"), let value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return value
    }
    public func save(to defaults: UserDefaults = AppSettings.preferences) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: "resetNewsInbox") }
    }
}
