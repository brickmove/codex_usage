import Foundation

public enum MenuMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case quotaRemaining, quotaUsed, credits, resetCountdown, resetTime, availableResets
    case cost, tokens, requests, cacheHitRate

    public var id: String { rawValue }
    public static let defaults: [MenuMetric] = [.quotaRemaining, .credits, .resetCountdown]
    public var title: String {
        switch self {
        case .quotaRemaining: return "剩余额度"
        case .quotaUsed: return "已用额度"
        case .credits: return "Credits 余额"
        case .resetCountdown: return "自动重置倒计时"
        case .resetTime: return "自动重置时间"
        case .availableResets: return "可用重置次数"
        case .cost: return "统计费用"
        case .tokens: return "Token 用量"
        case .requests: return "总请求数"
        case .cacheHitRate: return "缓存命中率"
        }
    }
    public var usesStatistics: Bool {
        switch self {
        case .cost, .tokens, .requests, .cacheHitRate: return true
        default: return false
        }
    }
    public var symbolName: String {
        switch self {
        case .quotaRemaining: return "gauge.with.dots.needle.50percent"
        case .quotaUsed: return "chart.pie"
        case .credits: return "creditcard"
        case .resetCountdown: return "clock.arrow.circlepath"
        case .resetTime: return "calendar"
        case .availableResets: return "arrow.counterclockwise"
        case .cost: return "dollarsign.circle"
        case .tokens: return "square.stack.3d.up"
        case .requests: return "arrow.up.arrow.down"
        case .cacheHitRate: return "bolt"
        }
    }
}

public struct MenuDisplayItem: Identifiable, Sendable {
    public let metric: MenuMetric
    public let value: String
    public let label: String
    public var id: String { metric.id }
}

public struct MenuPresentation: Sendable {
    public let items: [MenuDisplayItem]
    public let summary: String
    public let statisticsNotice: String?
}

/// Shared by the menu bar and the unsaved settings preview.
public enum MenuDisplay {
    public static func title(settings: AppSettings, quota: QuotaSnapshot?, statistics: UsageSummary?,
                             now: Date = Date(), quotaIsStale: Bool = false,
                             loadingQuota: Bool = false, loadingStatistics: Bool = false,
                             statisticsFailed: Bool = false, statisticsSyncState: StatisticsSyncState = .current) -> String {
        presentation(settings: settings, quota: quota, statistics: statistics, now: now,
                     quotaIsStale: quotaIsStale, loadingQuota: loadingQuota,
                     loadingStatistics: loadingStatistics, statisticsFailed: statisticsFailed,
                     statisticsSyncState: statisticsSyncState).summary
    }

    public static func presentation(settings: AppSettings, quota: QuotaSnapshot?, statistics: UsageSummary?,
                                    now: Date = Date(), quotaIsStale: Bool = false,
                                    loadingQuota: Bool = false, loadingStatistics: Bool = false,
                                    statisticsFailed: Bool = false, statisticsSyncState: StatisticsSyncState = .current) -> MenuPresentation {
        let metrics = settings.menuMetrics
        guard !metrics.isEmpty else { return MenuPresentation(items: [], summary: "", statisticsNotice: nil) }
        let window = quota?.preferredWindow
        let prefix = window.map { $0.windowDurationMins == nil ? "额度" : $0.title.replacingOccurrences(of: "额度", with: "") } ?? "额度"
        let quotaValid = quota != nil && !quotaIsStale
        let quotaMissing = loadingQuota && quota == nil ? "…" : "—"
        let unconfirmedZero = statisticsSyncState != .current && statistics?.totalRequests == 0
        let stats = statisticsFailed || unconfirmedZero ? nil : statistics
        let statisticsMissing = loadingStatistics && stats == nil ? "…" : "—"
        let scope: String
        switch settings.range {
        case .today: scope = "今日"
        case .last24Hours: scope = "近24小时"
        case .week: scope = "近7天"
        case .month: scope = "近30天"
        case .all: scope = "累计"
        case .custom: scope = "所选时段"
        }
        let items = metrics.map { metric -> MenuDisplayItem in
            func item(_ value: String, _ label: String) -> MenuDisplayItem {
                MenuDisplayItem(metric: metric, value: value, label: label)
            }
            switch metric {
            case .quotaRemaining:
                let value = quotaValid ? window.map { "\(Int($0.remainingPercent))%" } ?? quotaMissing : quotaMissing
                return item(value, "\(prefix)剩余 \(value)")
            case .quotaUsed:
                let value = quotaValid ? window.map { DisplayFormat.number($0.usedPercent, digits: 0) + "%" } ?? quotaMissing : quotaMissing
                return item(value, "\(prefix)已用 \(value)")
            case .credits:
                guard quotaValid, let credits = quota?.response.bucket?.credits else { return item(quotaMissing, "Credits \(quotaMissing)") }
                let value = credits.unlimited == true ? "∞" : credits.balance.map(DisplayFormat.compact) ?? "—"
                return item(value, "Credits \(value)")
            case .resetCountdown:
                guard quotaValid, let date = window?.resetDate else { return item(quotaMissing, "重置 \(quotaMissing)") }
                guard date > now else { return item("—", "重置待更新") }
                return item(DisplayFormat.countdown(to: date, now: now, compact: true),
                            DisplayFormat.countdown(to: date, now: now) + "后重置")
            case .resetTime:
                guard quotaValid, let date = window?.resetDate else { return item(quotaMissing, "重置时间 \(quotaMissing)") }
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "MM/dd HH:mm"
                let value = formatter.string(from: date)
                formatter.dateFormat = "M月d日 HH:mm"
                return item(value, "重置于 " + formatter.string(from: date))
            case .availableResets:
                guard quotaValid, let count = quota?.response.rateLimitResetCredits?.availableCount else { return item(quotaMissing, "可用重置 \(quotaMissing)") }
                return item(String(count), "可用重置 \(count) 次")
            case .cost:
                let value = stats.map { DisplayFormat.money($0.totalCost) } ?? statisticsMissing
                return item(value, "\(scope)费用 " + value)
            case .tokens:
                let value = stats.map { DisplayFormat.compact(Double($0.realTotalTokens)) } ?? statisticsMissing
                return item(value, "\(scope)用量 " + value + " Tokens")
            case .requests:
                let value = stats.map { DisplayFormat.compact(Double($0.totalRequests)) } ?? statisticsMissing
                return item(value, "\(scope)请求 " + value + " 次")
            case .cacheHitRate:
                guard let stats, stats.totalRequests > 0 else { return item(statisticsMissing, "\(scope)缓存命中 \(statisticsMissing)") }
                let value = DisplayFormat.number(stats.cacheHitRate * 100, digits: 1) + "%"
                return item(value, "\(scope)缓存命中 " + value)
            }
        }
        var parts = items.map(\.label)
        if quota != nil && quotaIsStale && metrics.contains(where: { !$0.usesStatistics }) { parts.append("额度待更新") }
        if statisticsFailed && metrics.contains(where: { $0.usesStatistics }) { parts.append("统计不可用") }
        let notice = metrics.contains(where: { $0.usesStatistics }) && !statisticsFailed ? statisticsSyncState.message : nil
        if let notice { parts.append(notice) }
        return MenuPresentation(items: items, summary: parts.joined(separator: " · "), statisticsNotice: notice)
    }
}
