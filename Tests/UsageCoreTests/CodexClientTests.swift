import XCTest
@testable import UsageCore

private final class AccountCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var account: CodexAccount?
    private var received = false
    func set(_ account: CodexAccount?) { lock.lock(); defer { lock.unlock() }; self.account = account; received = true }
    func get() -> (CodexAccount?, Bool) { lock.lock(); defer { lock.unlock() }; return (account, received) }
}

final class CodexClientTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("codex usage " + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private func executable(_ script: String) throws -> String {
        let path = folder.appendingPathComponent("fake-codex").path
        try ("#!/bin/sh\n" + script).write(toFile: path, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }
    private func responder(account: String = "{\"type\":\"chatgpt\"}", quota: String = "{\"rateLimits\":{\"primary\":{\"usedPercent\":20,\"windowDurationMins\":10080}}}") -> String {
        """
        while IFS= read -r line; do
          case "$line" in
            *'"id":1'*) printf '%s\\n' '{"id":1,"result":{}}' ;;
            *'"id":2'*) printf '%s\\n' '{"id":2,"result":{"account":\(account)}}' ;;
            *'"id":3'*) printf '%s\\n' '{"method":"account/rateLimits/updated","params":{}}' '{"id":3,"result":\(quota)}' ;;
          esac
        done
        """
    }
    func testStdioHandshakeIgnoresNotificationsAndHandlesPathsWithSpaces() throws {
        let path = try executable(responder())
        let quota = try CodexClient(executablePath: path, timeout: 2).readQuota()
        XCTAssertEqual(quota.preferredWindow?.remainingPercent, 80)
    }
    func testApiKeyAccountHasActionableError() throws {
        let path = try executable(responder(account: "{\"type\":\"apiKey\"}"))
        XCTAssertThrowsError(try CodexClient(executablePath: path, timeout: 2).readQuota()) {
            XCTAssertTrue($0.localizedDescription.contains("API Key"))
        }
    }
    func testLoggedOutAccountHasActionableError() throws {
        let path = try executable(responder(account: "null"))
        XCTAssertThrowsError(try CodexClient(executablePath: path, timeout: 2).readQuota()) {
            XCTAssertTrue($0.localizedDescription.contains("codex login"))
        }
    }
    func testTimeoutTerminatesSession() throws {
        let path = try executable("exec /bin/sleep 10\n")
        let start = Date()
        XCTAssertThrowsError(try CodexClient(executablePath: path, timeout: 0.1).readQuota()) {
            XCTAssertTrue($0.localizedDescription.contains("超时"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
    func testEarlyExitIsHandled() throws {
        let path = try executable("exit 1\n")
        XCTAssertThrowsError(try CodexClient(executablePath: path, timeout: 2).readQuota())
    }
    func testMissingExecutableDoesNotInvokeShell() {
        XCTAssertThrowsError(try CodexClient.locateExecutable(configured: "/does/not/exist; echo secrets"))
    }
    func testAccountIsReportedBeforeQuotaFailureWithoutReadingSecrets() throws {
        let path = try executable(responder(account: #"{"type":"chatgpt","email":"person@example.test","planType":"pro"}"#, quota: "{}"))
        let capture = AccountCapture()
        XCTAssertThrowsError(try CodexClient(executablePath: path, timeout: 2).readQuota(onAccount: { capture.set($0) }))
        XCTAssertEqual(capture.get().0, CodexAccount(type: "chatgpt", email: "person@example.test", planType: "pro"))
    }
    func testLoggedOutCallbackClearsPreviouslyIdentifiedAccount() throws {
        let path = try executable(responder(account: "null")), capture = AccountCapture()
        capture.set(CodexAccount(type: "chatgpt", email: "old@example.test"))
        XCTAssertThrowsError(try CodexClient(executablePath: path, timeout: 2).readQuota(onAccount: { capture.set($0) }))
        XCTAssertTrue(capture.get().1); XCTAssertNil(capture.get().0)
    }
}
