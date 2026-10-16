import AppKit

@MainActor
final class StatisticsSourceController {
    static let bundleIdentifier = "com.ccswitch.desktop"
    static var isRunning: Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).contains { !$0.isTerminated }
    }
    private var isLaunching = false
    private var lastAutomaticAttempt: Date?

    func open(activate: Bool, completion: @escaping @MainActor (String?) -> Void) {
        if Self.isRunning && !activate {
            completion(nil)
            return
        }
        guard !isLaunching else { return }
        if !activate {
            guard Date().timeIntervalSince(lastAutomaticAttempt ?? .distantPast) >= 60 else { return }
            lastAutomaticAttempt = Date()
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            completion("未找到 CC Switch，请先安装后再同步统计。")
            return
        }
        isLaunching = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = activate
        configuration.hides = !activate
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                self?.isLaunching = false
                completion(error.map { "无法启动 CC Switch：" + $0.localizedDescription })
            }
        }
    }
}
