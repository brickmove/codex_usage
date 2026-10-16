import AppKit
import SwiftUI
import UsageCore

@main
struct CodexUsageMain {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.contains("--help") {
            print("""
            Codex Usage — macOS 菜单栏工具
            直接运行：打开菜单栏工具
            --settings：启动并打开设置窗口
            --diagnose [--statistics-only] [--range today|last24Hours|week|month|all]
                       [--database PATH] [--codex-path PATH] [--codex-home PATH]
            --preview OUTPUT.png [--dark] [--unsynced] [--stale] [--compact-panel]：导出示例预览
            --preview-analysis OUTPUT.png [--dark] [--empty] [--failed]：导出 Token 构成预览
            --preview-settings OUTPUT.png [--dark] [--section menu|appearance|data|news]：导出设置预览
            --demo [--settings]：运行隔离示例界面，不保存设置或查询账户
            示例与预览还支持 --theme teal|ocean|forest|iris|sand|graphite 和 --appearance system|light|dark
            --preview-news OUTPUT.png [--dark]：导出重置动态示例预览
            --diagnose-news：检查 AIHOT 重置动态（遵守缓存与检查间隔）
            --diagnose-wake：模拟唤醒恢复，输出可用状态，不输出邮箱或凭据
            """)
            return
        }
        if args.contains("--diagnose") { diagnose(args); return }
        if args.contains("--diagnose-news") { diagnoseNews(); return }
        if args.contains("--diagnose-wake") { diagnoseWake(); return }
        let app = NSApplication.shared
        if let index = args.firstIndex(where: { ["--preview", "--preview-settings", "--preview-news", "--preview-analysis"].contains($0) }), args.indices.contains(index + 1) {
            do { try preview(path: args[index + 1], args: args) }
            catch { fputs("预览失败：\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        let model = args.contains("--demo") ? AppModel.previewModel() : AppModel()
        if model.isPreview {
            do { try configureAppearance(args: args, model: model) }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
        }
        let delegate = AppDelegate(model: model); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    @MainActor private static func diagnoseWake() {
        var settings = AppSettings.load(); settings.resetNewsEnabled = false
        let model = AppModel(initialSettings: settings, persists: false)
        model.prepareForSleep(); model.recoverAfterWake()
        let deadline = Date().addingTimeInterval(45)
        while model.isRecovering && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let output: [String: Any] = [
            "simulatedWake": true, "quotaAvailable": model.quota != nil && model.quotaError == nil,
            "statisticsAvailable": model.statistics != nil && model.statisticsError == nil,
            "accountVerified": model.accountIsVerified, "accountDetected": model.account != nil,
            "hasEmail": model.account?.email != nil, "authType": model.account?.type ?? "unknown",
            "recoveryFinished": !model.isRecovering
        ]
        let succeeded = model.quota != nil && model.quotaError == nil && model.statistics != nil && model.statisticsError == nil && !model.isRecovering
        model.stop()
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        if !succeeded { exit(1) }
    }

    @MainActor private static func diagnose(_ args: [String]) {
        func option(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
            return args[i + 1]
        }
        var settings = AppSettings.load()
        settings.databasePath = option("--database") ?? settings.databasePath
        settings.codexPath = option("--codex-path") ?? settings.codexPath
        settings.codexHome = option("--codex-home") ?? settings.codexHome
        if let range = option("--range") {
            guard let preset = RangePreset(rawValue: range), preset != .custom else {
                fputs("无效范围；请选择 today、last24Hours、week、month 或 all。\n", stderr); exit(1)
            }
            settings.range = preset
        }
        var output: [String: Any] = [:], failed = false
        do {
            let range = try settings.resolvedRange()
            let summary = try StatisticsReader(path: settings.databasePath, codexHome: settings.codexHome).read(range: range)
            output["statistics"] = [
                "range": settings.range.rawValue,
                "start": ISO8601DateFormatter().string(from: range.start),
                "end": ISO8601DateFormatter().string(from: range.end),
                "totalRequests": summary.totalRequests,
                "storedCostUSD": summary.totalCost,
                "realTotalTokens": summary.realTotalTokens,
                "cacheHitRate": summary.cacheHitRate,
                "archiveBoundaryOmitted": summary.archiveBoundaryOmitted,
                "lastSyncedAt": summary.lastSyncedAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown",
                "latestRecordAt": summary.latestRecordAt.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown",
                "sourceIsRunning": StatisticsSourceController.isRunning,
                "syncState": StatisticsSyncState.evaluate(summary: summary, range: range,
                                      sourceIsRunning: StatisticsSourceController.isRunning, now: Date()).rawValue
            ] as [String: Any]
        } catch { output["statisticsError"] = error.localizedDescription; failed = true }
        if !args.contains("--statistics-only") {
            do {
                let q = try CodexClient(executablePath: settings.codexPath, codexHome: settings.codexHome).readQuota()
                var result: [String: Any] = ["plan": q.response.bucket?.planType ?? "unknown"]
                if let w = q.preferredWindow {
                    result["windowDurationMins"] = w.windowDurationMins
                    result["remainingPercent"] = w.remainingPercent
                    result["resetsAt"] = w.resetDate.map { ISO8601DateFormatter().string(from: $0) }
                }
                result["credits"] = q.response.bucket?.credits?.balance
                result["unlimitedCredits"] = q.response.bucket?.credits?.unlimited
                result["availableResets"] = q.response.rateLimitResetCredits?.availableCount
                output["quota"] = result
            } catch { output["quotaError"] = error.localizedDescription; failed = true }
        }
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        if failed { exit(1) }
    }

    private static func diagnoseNews() {
        var inbox = ResetNewsInbox.load()
        guard inbox.canFetch() else {
            printNewsDiagnostic(inbox, mode: "cached")
            if inbox.feed == nil || inbox.lastError != nil { exit(1) }
            return
        }
        inbox.beginAttempt(); inbox.save()
        let completion = DispatchSemaphore(value: 0)
        let current = inbox
        Task.detached {
            var state = current
            do {
                let result = try await ResetNewsClient().fetch(etag: state.feed == nil ? nil : state.etag)
                if let feed = result.feed { state.receive(feed, etag: result.etag) }
                else { try state.recordNotModified(); state.etag = result.etag }
                state.save()
                printNewsDiagnostic(state, mode: result.feed == nil ? "notModified" : "updated")
            } catch {
                state.recordFailure(error.localizedDescription, retryAt: (error as? ResetNewsHTTPError)?.retryAt)
                state.save()
                fputs("\(error.localizedDescription)\n", stderr)
                exit(1)
            }
            completion.signal()
        }
        if completion.wait(timeout: .now() + 25) == .timedOut { fputs("重置动态诊断超时。\n", stderr); exit(1) }
    }
    private static func printNewsDiagnostic(_ inbox: ResetNewsInbox, mode: String) {
        var output: [String: Any] = ["mode": mode, "unreadCount": inbox.unreadIDs.count, "source": ResetNewsSource.pageURL.absoluteString]
        if let feed = inbox.feed {
            output["eventCount"] = feed.events.count
            output["pendingCount"] = feed.events.filter { !$0.isConfirmed }.count
            output["monitor"] = feed.monitor?.status ?? "unknown"
            output["checkedAt"] = feed.checkedAt.map { ISO8601DateFormatter().string(from: $0) }
        }
        if let error = inbox.lastError { output["error"] = error }
        if let data = try? JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) { print(text) }
    }
    @MainActor private static func preview(path: String, args: [String]) throws {
        let dark = args.contains("--dark"), settings = args.contains("--preview-settings")
        let model = AppModel.previewModel(unsynced: args.contains("--unsynced"))
        model.settings.appearance = dark ? .dark : .light
        try configureAppearance(args: args, model: model)
        model.statistics?.queriedRange = try? model.settings.resolvedRange(now: model.now)
        if args.contains("--preview-news") { model.selectedTab = .resetNews }
        if args.contains("--preview-analysis") { model.selectedTab = .analysis }
        if args.contains("--stale") { model.quota?.queriedAt = model.now.addingTimeInterval(-3600) }
        if args.contains("--empty") {
            var empty = UsageSummary(); empty.lastSyncedAt = model.now
            empty.queriedRange = model.statistics?.queriedRange; model.statistics = empty
        }
        if args.contains("--failed") { model.statisticsError = "示例：暂时无法读取数据库，请重试。" }
        if args.contains("--invalid-range") {
            model.settings.range = .custom
            model.settings.customStart = model.now.addingTimeInterval(3600); model.settings.customEnd = model.now
        }
        if args.contains("--compact-panel") { model.panelHeight = PanelLayout.height(availableHeight: 550) }
        var category: SettingsCategory = .menu
        if let i = args.firstIndex(of: "--section"), args.indices.contains(i + 1) {
            category = SettingsCategory(rawValue: args[i + 1]) ?? .menu
        }
        let content = (settings ? AnyView(SettingsView(model: model, initialCategory: category, close: {})) : AnyView(PopoverView(model: model)))
            .environment(\.colorScheme, dark ? .dark : .light)
        let size = NSSize(width: settings ? 520 : 400, height: settings ? 650 : model.panelHeight)
        let view = NSHostingView(rootView: content)
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = view.appearance
        window.contentView = view
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded()
        // Let AppKit controls apply their initial SwiftUI selection before offscreen capture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UsageError.message("无法创建位图") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw UsageError.message("无法导出 PNG") }
        try png.write(to: URL(fileURLWithPath: AppSettings.expandedPath(path)))
        print("已导出示例数据预览：\(path)")
    }

    @MainActor private static func configureAppearance(args: [String], model: AppModel) throws {
        if let index = args.firstIndex(of: "--theme") {
            guard args.indices.contains(index + 1), let theme = AppTheme(rawValue: args[index + 1]) else {
                throw UsageError.message("无效主题；请选择 teal、ocean、forest、iris、sand 或 graphite。")
            }
            model.settings.theme = theme
        }
        if let index = args.firstIndex(of: "--appearance") {
            guard args.indices.contains(index + 1), let appearance = AppAppearance(rawValue: args[index + 1]) else {
                throw UsageError.message("无效外观；请选择 system、light 或 dark。")
            }
            model.settings.appearance = appearance
        }
    }
}
