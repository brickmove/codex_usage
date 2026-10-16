import Foundation
import UsageCore

struct AppServices: Sendable {
    var readQuota: @Sendable (AppSettings, @escaping @Sendable (CodexAccount?) -> Void) async throws -> QuotaSnapshot = { settings, onAccount in
        let worker = Task.detached(priority: .utility) {
            try CodexClient(executablePath: settings.codexPath, codexHome: settings.codexHome).readQuota(onAccount: onAccount)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }
    var readStatistics: @Sendable (AppSettings, UsageRange) async throws -> UsageSummary = { settings, range in
        let worker = Task.detached(priority: .utility) {
            try StatisticsReader(path: settings.databasePath, codexHome: settings.codexHome).read(range: range)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: { worker.cancel() }
    }
    var sleep: @Sendable (TimeInterval) async throws -> Void = { seconds in
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
