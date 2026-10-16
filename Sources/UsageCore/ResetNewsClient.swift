import Foundation

public struct ResetNewsHTTPError: LocalizedError {
    public let status: Int
    public let retryAt: Date?
    public var errorDescription: String? {
        if status == 429 { return "AIHOT 请求较频繁，将在允许的时间后重试。" }
        if status == 503 { return "AIHOT 暂时不可用，稍后自动重试。" }
        return "AIHOT 重置动态获取失败（HTTP \(status)）。"
    }
}

public struct ResetNewsResult: Sendable {
    public var feed: ResetNewsFeed?
    public var etag: String?
}

public struct ResetNewsClient: Sendable {
    private let session: URLSession
    public init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let config = URLSessionConfiguration.ephemeral
            config.httpShouldSetCookies = false
            config.urlCredentialStorage = nil
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: config)
        }
    }
    public func fetch(etag: String? = nil, now: Date = Date()) async throws -> ResetNewsResult {
        var request = URLRequest(url: ResetNewsSource.feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("aihot-api/2.0.0 CodexUsage/0.3.0", forHTTPHeaderField: "User-Agent")
        request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch { throw UsageError.message("暂时无法连接 AIHOT，请检查网络。已缓存的动态仍可查看。") }
        guard let http = response as? HTTPURLResponse else { throw UsageError.message("AIHOT 返回了无效响应。") }
        if http.statusCode == 304 { return ResetNewsResult(feed: nil, etag: http.value(forHTTPHeaderField: "ETag") ?? etag) }
        guard http.statusCode == 200 else {
            throw ResetNewsHTTPError(status: http.statusCode, retryAt: Self.retryDate(http.value(forHTTPHeaderField: "Retry-After"), now: now))
        }
        guard data.count <= 2 * 1024 * 1024 else { throw UsageError.message("AIHOT 重置动态响应过大，请查看来源网页。") }
        return ResetNewsResult(feed: try ResetNewsFeed.decode(data), etag: http.value(forHTTPHeaderField: "ETag"))
    }
    public static func retryDate(_ value: String?, now: Date) -> Date? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 { return now.addingTimeInterval(seconds) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter.date(from: value)
    }
}
