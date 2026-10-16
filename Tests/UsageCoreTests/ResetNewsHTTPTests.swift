import XCTest
@testable import UsageCore

private final class NewsURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class ResetNewsHTTPTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NewsURLProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { session.invalidateAndCancel(); NewsURLProtocol.handler = nil }
    func testPublicJSONRequestUsesETagCompressionAndNoCredentials() async throws {
        let data = try NewsFixture.data()
        NewsURLProtocol.handler = { request in
            XCTAssertEqual(request.url, ResetNewsSource.feedURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "previous")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept-Encoding"), "gzip")
            XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("aihot-api/2.0.0") == true)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["ETag": "next"])!, data)
        }
        let result = try await ResetNewsClient(session: session).fetch(etag: "previous")
        XCTAssertEqual(result.feed?.events.count, 1); XCTAssertEqual(result.etag, "next")
    }
    func testNotModifiedDoesNotTryToDecodeEmptyBody() async throws {
        NewsURLProtocol.handler = { (HTTPURLResponse(url: $0.url!, statusCode: 304, httpVersion: nil, headerFields: nil)!, Data()) }
        let result = try await ResetNewsClient(session: session).fetch(etag: "same")
        XCTAssertNil(result.feed); XCTAssertEqual(result.etag, "same")
    }
    func testRateLimitIncludesRetryAfter() async {
        NewsURLProtocol.handler = { (HTTPURLResponse(url: $0.url!, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "1800"])!, Data()) }
        do { _ = try await ResetNewsClient(session: session).fetch(now: NewsFixture.now); XCTFail("Expected rate limit") }
        catch let error as ResetNewsHTTPError { XCTAssertEqual(error.retryAt, NewsFixture.now.addingTimeInterval(1800)) }
        catch { XCTFail("Unexpected error: \(error)") }
    }
    func testNetworkFailureIsActionable() async {
        NewsURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do { _ = try await ResetNewsClient(session: session).fetch(); XCTFail("Expected network error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("无法连接 AIHOT")) }
    }
    func testHTMLResponseIsNotRenderedAsNews() async {
        NewsURLProtocol.handler = { (HTTPURLResponse(url: $0.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("<html>unavailable</html>".utf8)) }
        do { _ = try await ResetNewsClient(session: session).fetch(); XCTFail("Expected decoding error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("无法解析")) }
    }
    func testHTTPDateRetryAfter() {
        let date = ResetNewsClient.retryDate("Thu, 15 Oct 2026 12:00:00 GMT", now: NewsFixture.now)
        XCTAssertEqual(date?.timeIntervalSince1970, 1792065600)
    }
}
