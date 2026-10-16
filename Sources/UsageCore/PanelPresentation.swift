import Foundation

/// 文字、图形与辅助功能共用有效性，避免隐藏大数字后仍暴露旧进度。
public struct RateWindowPresentation: Sendable {
    public let isCurrent: Bool
    public let remainingText: String
    public let usedText: String
    public let progress: Double?
    public let accessibilitySummary: String

    public init(window: RateWindow, now: Date, quotaIsStale: Bool) {
        isCurrent = !quotaIsStale && (window.resetDate.map { $0 > now } ?? true)
        remainingText = isCurrent ? DisplayFormat.number(window.remainingPercent, digits: 0) + "%" : "—"
        usedText = isCurrent ? "已用 " + DisplayFormat.number(window.usedPercent, digits: 0) + "%" : "额度待更新"
        progress = isCurrent ? window.remainingPercent / 100 : nil
        var summary = window.title + (isCurrent ? "，剩余 " + remainingText + "，" + usedText : "，额度待更新")
        if isCurrent, let date = window.resetDate {
            summary += "，自动重置 " + date.formatted(.dateTime.month().day().hour().minute())
        }
        accessibilitySummary = summary
    }
}

/// 账户级余额和重置详情使用同一快照状态，失效时不显示旧估值或到期信息。
public struct AccountQuotaPresentation: Sendable {
    public let creditsText: String
    public let estimatedValueText: String?
    public let availableResetsText: String
    public let nextExpiryText: String?

    public init(snapshot: QuotaSnapshot, now: Date, isStale: Bool) {
        guard !isStale else {
            creditsText = "—"; estimatedValueText = nil
            availableResetsText = "—"; nextExpiryText = nil
            return
        }
        let credits = snapshot.response.bucket?.credits
        if credits?.unlimited == true {
            creditsText = "不限量"; estimatedValueText = nil
        } else {
            creditsText = credits?.balance.map { DisplayFormat.number($0) } ?? "未提供"
            estimatedValueText = credits?.balance.map { "约 $" + DisplayFormat.number(($0 * 0.04).rounded(), digits: 0) }
        }
        availableResetsText = snapshot.response.rateLimitResetCredits.map { "\($0.availableCount) 次" } ?? "未提供"
        nextExpiryText = snapshot.response.rateLimitResetCredits?.nextExpiry(now: now)
            .map { "已知最早到期 " + $0.formatted(.dateTime.month().day()) }
    }
}

public enum TokenKind: String, Sendable, CaseIterable, Identifiable {
    case freshInput, output, cacheWrite, cacheRead
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .freshInput: return "新增输入"
        case .output: return "输出"
        case .cacheWrite: return "缓存写入"
        case .cacheRead: return "缓存命中"
        }
    }
}

public struct TokenComponent: Sendable, Identifiable {
    public let kind: TokenKind
    public let tokens: Int64
    public let fraction: Double?
    public var id: String { kind.id }
}

public extension UsageSummary {
    /// 构成份额含输出；不同于以全部输入为分母的 cacheHitRate，不进行费用计算。
    var tokenBreakdown: [TokenComponent] {
        zip(TokenKind.allCases, [freshInput, output, cacheWrite, cacheRead]).map { kind, count in
            TokenComponent(kind: kind, tokens: count,
                           fraction: realTotalTokens > 0 ? Double(count) / Double(realTotalTokens) : nil)
        }
    }
}

public extension UsageRange {
    /// 两个日期入口复用真实范围验证，提示不会变成数据库读取错误。
    static func validationMessage(start: Date, end: Date) -> String? {
        do { _ = try UsageRange(start: start, end: end); return nil }
        catch { return error.localizedDescription }
    }
}

public enum PanelLayout {
    /// 留出 popover 箭头与边缘空间；SwiftUI 与 AppKit 必须使用同一结果。
    public static func height(availableHeight: Double) -> Double {
        min(660, max(1, availableHeight - 32))
    }
}
