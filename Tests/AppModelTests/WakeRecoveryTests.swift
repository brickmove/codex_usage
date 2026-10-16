import XCTest
import UsageCore
@testable import CodexUsage

private actor RecoveryBackend {
    var quotaCalls = 0
    var statisticsCalls = 0
    var failures: Int
    let holdFirst: Bool
    private var oldQuota: CheckedContinuation<QuotaSnapshot, Error>?
    private var oldStatistics: CheckedContinuation<UsageSummary, Error>?
    private var oldAccountCallback: (@Sendable (CodexAccount?) -> Void)?

    init(failures: Int = 0, holdFirst: Bool = false) { self.failures = failures; self.holdFirst = holdFirst }

    func quota(onAccount: @escaping @Sendable (CodexAccount?) -> Void) async throws -> QuotaSnapshot {
        quotaCalls += 1
        if holdFirst && quotaCalls == 1 {
            oldAccountCallback = onAccount
            return try await withCheckedThrowingContinuation { oldQuota = $0 }
        }
        onAccount(CodexAccount(type: "chatgpt", email: "current@example.test", planType: "pro"))
        if quotaCalls <= failures { throw UsageError.message("模拟唤醒后网络尚未恢复") }
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080},"planType":"pro"}}"#.utf8)
        return QuotaSnapshot(response: try JSONDecoder().decode(RateLimitsResponse.self, from: data), email: "current@example.test")
    }
    func statistics(range: UsageRange) async throws -> UsageSummary {
        statisticsCalls += 1
        if holdFirst && statisticsCalls == 1 {
            return try await withCheckedThrowingContinuation { oldStatistics = $0 }
        }
        var result = UsageSummary(); result.totalRequests = 7; result.freshInput = 123
        result.queriedRange = range; result.lastSyncedAt = Date()
        return result
    }
    func releaseOldRequests() {
        oldAccountCallback?(CodexAccount(type: "chatgpt", email: "old@example.test"))
        oldQuota?.resume(throwing: UsageError.message("模拟休眠前的旧请求失败")); oldQuota = nil
        var old = UsageSummary(); old.totalRequests = 999
        oldStatistics?.resume(returning: old); oldStatistics = nil
    }
}

@MainActor
final class WakeRecoveryTests: XCTestCase {
    private func model(_ backend: RecoveryBackend, delays: [TimeInterval] = [0, 0, 0], realSleep: Bool = false) -> AppModel {
        var settings = AppSettings()
        settings.quotaInterval = 0; settings.statisticsInterval = 0; settings.resetNewsEnabled = false
        var services = AppServices()
        services.readQuota = { _, onAccount in try await backend.quota(onAccount: onAccount) }
        services.readStatistics = { _, range in try await backend.statistics(range: range) }
        if !realSleep { services.sleep = { _ in await Task.yield() } }
        return AppModel(initialSettings: settings, services: services, persists: false, recoveryDelays: delays)
    }
    private func waitUntil(_ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate() {
            if Date() > deadline { XCTFail("等待模型状态超时"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    private func waitForCalls(_ backend: RecoveryBackend, quota: Int, statistics: Int = 0) async throws {
        let deadline = Date().addingTimeInterval(3)
        while true {
            let quotaCalls = await backend.quotaCalls, statisticsCalls = await backend.statisticsCalls
            if quotaCalls >= quota && statisticsCalls >= statistics { return }
            if Date() > deadline { XCTFail("等待请求启动超时"); return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
    func testWakeRetriesUntilNetworkRecoversEvenInManualRefreshMode() async throws {
        let backend = RecoveryBackend(failures: 2), model = model(backend)
        model.recoverAfterWake()
        try await waitUntil { !model.isRecovering }
        let calls = await backend.quotaCalls
        XCTAssertEqual(calls, 3)
        XCTAssertNil(model.quotaError)
        XCTAssertEqual(model.quota?.preferredWindow?.remainingPercent, 80)
        XCTAssertEqual(model.statistics?.totalRequests, 7)
        XCTAssertEqual(model.account?.email, "current@example.test")
        XCTAssertTrue(model.accountIsVerified)
    }
    func testRepeatedWakeNotificationsAreCoalesced() async throws {
        let backend = RecoveryBackend(), model = model(backend)
        model.recoverAfterWake(); model.recoverAfterWake(); model.recoverAfterWake()
        try await waitUntil { !model.isRecovering }
        let calls = await backend.quotaCalls
        XCTAssertEqual(calls, 1)
    }
    func testPreSleepResponsesAndAccountCannotOverwriteRecoveredData() async throws {
        let backend = RecoveryBackend(holdFirst: true), model = model(backend)
        model.refreshAll()
        try await waitForCalls(backend, quota: 1, statistics: 1)
        model.prepareForSleep(); model.recoverAfterWake()
        try await waitUntil { !model.isRecovering }
        await backend.releaseOldRequests()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertNil(model.quotaError)
        XCTAssertEqual(model.quota?.preferredWindow?.remainingPercent, 80)
        XCTAssertEqual(model.statistics?.totalRequests, 7)
        XCTAssertEqual(model.account?.email, "current@example.test")
        XCTAssertFalse(model.loadingQuota); XCTAssertFalse(model.loadingStatistics)
    }
    func testAccountRemainsVisibleWhenEveryQuotaRequestFails() async throws {
        let backend = RecoveryBackend(failures: 10), model = model(backend)
        model.recoverAfterWake()
        try await waitUntil { !model.isRecovering }
        XCTAssertNotNil(model.quotaError)
        XCTAssertNil(model.quota)
        XCTAssertEqual(model.account?.displayName, "current@example.test")
        XCTAssertTrue(model.accountIsVerified)
        XCTAssertEqual(model.statistics?.totalRequests, 7)
    }
    func testNetworkRecoveryTriggersAnotherReadAfterRetriesEnded() async throws {
        let backend = RecoveryBackend(failures: 1), model = model(backend, delays: [0])
        model.recoverAfterWake()
        try await waitUntil { !model.isRecovering }
        XCTAssertNotNil(model.quotaError)
        model.networkBecameAvailable()
        try await waitUntil { !model.isRecovering }
        XCTAssertNil(model.quotaError)
        XCTAssertNotNil(model.quota)
        let calls = await backend.quotaCalls
        XCTAssertEqual(calls, 2)
    }
    func testSleepCancelsScheduledWakeRetry() async throws {
        let backend = RecoveryBackend(failures: 10), model = model(backend, delays: [0, 60], realSleep: true)
        model.recoverAfterWake()
        try await waitUntil { model.quotaError != nil }
        model.prepareForSleep()
        try await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertFalse(model.isRecovering)
        XCTAssertFalse(model.accountIsVerified)
        let calls = await backend.quotaCalls
        XCTAssertEqual(calls, 1)
    }
    func testDelayedIdentityCallbackDoesNotClearSuccessfulQuota() async throws {
        var settings = AppSettings(); settings.resetNewsEnabled = false
        var services = AppServices()
        services.readQuota = { _, onAccount in
            Task {
                try? await Task.sleep(nanoseconds: 20_000_000)
                onAccount(CodexAccount(type: "chatgpt", email: "current@example.test", planType: "pro"))
            }
            let data = Data(#"{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080},"planType":"pro"}}"#.utf8)
            return QuotaSnapshot(response: try JSONDecoder().decode(RateLimitsResponse.self, from: data), email: "current@example.test")
        }
        services.readStatistics = { _, _ in var result = UsageSummary(); result.totalRequests = 1; return result }
        let model = AppModel(initialSettings: settings, services: services, persists: false, recoveryDelays: [0])
        model.recoverAfterWake()
        try await waitUntil { !model.isRecovering }
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(model.quota?.preferredWindow?.remainingPercent, 80)
        XCTAssertEqual(model.account?.email, "current@example.test")
    }
}
