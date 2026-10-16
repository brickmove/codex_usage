import Foundation

public enum StatisticsSyncState: String, Sendable, Equatable {
    case current, sourceNotRunning, waitingForSync, delayed

    public var message: String? {
        switch self {
        case .current: return nil
        case .sourceNotRunning: return "CC Switch 未运行，统计更新已暂停"
        case .waitingForSync: return "等待 CC Switch 同步用量"
        case .delayed: return "统计源超过 10 分钟未更新"
        }
    }

    public static func evaluate(summary: UsageSummary, range: UsageRange,
                                sourceIsRunning: Bool, now: Date) -> Self {
        // A closed source does not invalidate a historical range already covered by a sync.
        if let synced = summary.lastSyncedAt, synced >= range.end { return .current }
        guard sourceIsRunning else { return .sourceNotRunning }
        guard let reference = summary.lastSyncedAt ?? summary.latestRecordAt else { return .waitingForSync }
        if summary.totalRequests == 0 && reference < range.start { return .waitingForSync }
        return now.timeIntervalSince(reference) > 600 ? .delayed : .current
    }
}
