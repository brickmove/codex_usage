import Foundation
import Combine
import UsageCore

enum PanelTab: String, CaseIterable, Identifiable {
    case usage, resetNews
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings { didSet { if !isPreview && persists { settings.save() } } }
    @Published var quota: QuotaSnapshot?
    @Published var statistics: UsageSummary?
    @Published var quotaError: String?
    @Published var statisticsError: String?
    @Published var loadingQuota = false
    @Published var loadingStatistics = false
    @Published private(set) var account: CodexAccount?
    @Published private(set) var accountIsVerified = false
    @Published private(set) var isRecovering = false
    @Published private(set) var statisticsSourceRunning = StatisticsSourceController.isRunning
    @Published private(set) var statisticsSourceError: String?
    @Published var now = Date()
    @Published var newsInbox: ResetNewsInbox
    @Published var loadingNews = false
    @Published var selectedTab: PanelTab = .usage {
        didSet { if selectedTab == .resetNews && isPanelVisible { markNewsRead() } }
    }
    var showSettings: () -> Void = {}
    var dismissPopover: () -> Void = {}
    let isPreview: Bool
    private let previewSyncState: StatisticsSyncState
    private let persists: Bool
    private let services: AppServices
    private let recoveryDelays: [TimeInterval]
    private var timer: Timer?
    private var lastQuotaAttempt: Date?
    private var lastStatisticsAttempt: Date?
    private var pendingQuota = false
    private var pendingStatistics = false
    private var isPanelVisible = false
    private let statisticsSource = StatisticsSourceController()
    private var quotaTask: Task<Void, Never>?
    private var statisticsTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var quotaRequestID = UUID()
    private var statisticsRequestID = UUID()
    private var recoveryID = UUID()
    private var lastWakeEventAt: Date?

    init(preview: Bool = false, previewSyncState: StatisticsSyncState = .current,
         initialSettings: AppSettings? = nil, services: AppServices = AppServices(), persists: Bool = true,
         recoveryDelays: [TimeInterval] = [0, 2, 5, 10, 20, 30, 60]) {
        isPreview = preview
        self.previewSyncState = previewSyncState
        self.persists = persists; self.services = services; self.recoveryDelays = recoveryDelays
        settings = initialSettings ?? (preview ? AppSettings() : AppSettings.load())
        newsInbox = preview || !persists ? ResetNewsInbox() : ResetNewsInbox.load()
    }
    func start() {
        guard !isPreview else { return }
        refreshAll()
        timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 1
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }
    func tick() {
        now = Date()
        updateStatisticsSource()
        if let range = statistics?.queriedRange, settings.range.needsDayRolloverRefresh(queriedRange: range, now: now) {
            statistics = nil; statisticsError = nil
            refreshStatistics()
        }
        if settings.quotaInterval > 0 && now.timeIntervalSince(lastQuotaAttempt ?? .distantPast) >= settings.quotaInterval { refreshQuota() }
        if settings.statisticsInterval > 0 && now.timeIntervalSince(lastStatisticsAttempt ?? .distantPast) >= settings.statisticsInterval { refreshStatistics() }
        if settings.resetNewsEnabled && settings.resetNewsInterval > 0
            && now.timeIntervalSince(newsInbox.lastAttemptAt ?? .distantPast) >= max(600, settings.resetNewsInterval) { refreshNews() }
    }
    func refreshAll() { refreshQuota(); refreshStatistics(); refreshNews() }
    func prepareForSleep() {
        lastWakeEventAt = nil
        recoveryID = UUID(); recoveryTask?.cancel(); recoveryTask = nil
        invalidateRequests()
        accountIsVerified = false; isRecovering = false
    }
    private func invalidateRequests() {
        quotaRequestID = UUID(); statisticsRequestID = UUID()
        quotaTask?.cancel(); statisticsTask?.cancel()
        quotaTask = nil; statisticsTask = nil
        loadingQuota = false; loadingStatistics = false
        pendingQuota = false; pendingStatistics = false
    }
    func recoverAfterWake(force: Bool = false) {
        guard !isPreview else { return }
        if !force, let lastWakeEventAt, Date().timeIntervalSince(lastWakeEventAt) < 2 { return }
        lastWakeEventAt = Date()
        recoveryTask?.cancel(); invalidateRequests()
        let id = UUID(); recoveryID = id
        now = Date(); accountIsVerified = false; isRecovering = true
        recoveryTask = Task { [weak self] in
            guard let self else { return }
            for delay in self.recoveryDelays {
                do { if delay > 0 { try await self.services.sleep(delay) } }
                catch { break }
                guard !Task.isCancelled, self.recoveryID == id else { return }
                self.now = Date()
                self.refreshAll()
                let quota = self.quotaTask, statistics = self.statisticsTask
                await quota?.value; await statistics?.value
                guard !Task.isCancelled, self.recoveryID == id else { return }
                let quotaComplete = self.quotaError == nil && self.quota != nil && !self.loadingQuota
                let statisticsComplete = self.statisticsError == nil && self.statistics != nil && !self.loadingStatistics
                if quotaComplete && statisticsComplete { break }
                if self.accountIsVerified && self.account?.type != "chatgpt" && statisticsComplete { break }
            }
            guard self.recoveryID == id else { return }
            self.isRecovering = false; self.recoveryTask = nil
        }
    }
    func networkBecameAvailable() {
        if isRecovering || quotaError != nil || statisticsError != nil { recoverAfterWake(force: true) }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        prepareForSleep()
    }
    func resumeIfNeeded() {
        tick()
        if !isRecovering && (quotaError != nil || statisticsError != nil) { recoverAfterWake() }
    }
    var unreadNewsCount: Int { newsInbox.unreadIDs.count }
    var showNewsIndicator: Bool { newsIndicator(for: settings) }
    func newsIndicator(for configuration: AppSettings) -> Bool {
        newsInbox.shouldShowIndicator(enabled: configuration.showResetNewsIndicator, monitoring: configuration.resetNewsEnabled)
    }
    var canRefreshNews: Bool { settings.resetNewsEnabled && !loadingNews && newsInbox.canFetch(at: now) }
    func setPanelVisible(_ visible: Bool) {
        isPanelVisible = visible
        if visible && selectedTab == .resetNews { markNewsRead() }
    }
    func markNewsRead() {
        guard !newsInbox.unreadIDs.isEmpty else { return }
        newsInbox.markRead()
        if !isPreview && persists { newsInbox.save() }
    }
    func refreshNews() {
        guard !isPreview, canRefreshNews else { return }
        loadingNews = true
        newsInbox.beginAttempt()
        if persists { newsInbox.save() }
        let etag = newsInbox.feed == nil ? nil : newsInbox.etag
        Task {
            do {
                let result = try await ResetNewsClient().fetch(etag: etag)
                if let feed = result.feed { self.newsInbox.receive(feed, etag: result.etag) }
                else {
                    try self.newsInbox.recordNotModified()
                    self.newsInbox.etag = result.etag
                }
                if self.isPanelVisible && self.selectedTab == .resetNews { self.newsInbox.markRead() }
            } catch {
                self.newsInbox.recordFailure(error.localizedDescription, retryAt: (error as? ResetNewsHTTPError)?.retryAt)
            }
            self.loadingNews = false; self.now = Date()
            if self.persists { self.newsInbox.save() }
        }
    }
    func apply(_ newSettings: AppSettings) {
        let sourceChanged = newSettings.codexPath != settings.codexPath || newSettings.codexHome != settings.codexHome
        let databaseChanged = newSettings.databasePath != settings.databasePath
        let rangeChanged = newSettings.range != settings.range || newSettings.customStart != settings.customStart
            || newSettings.customEnd != settings.customEnd
        settings = newSettings
        if sourceChanged { quota = nil; quotaError = nil; account = nil; accountIsVerified = false }
        if sourceChanged || databaseChanged || rangeChanged { statistics = nil; statisticsError = nil }
        refreshAll()
    }
    func setRange(_ preset: RangePreset) {
        guard settings.range != preset else { return }
        settings.range = preset
        statistics = nil; statisticsError = nil
        refreshStatistics()
    }
    func setCustomRange(start: Date, end: Date) {
        do { _ = try UsageRange(start: start, end: end) }
        catch { statisticsError = error.localizedDescription; return }
        settings.customStart = start; settings.customEnd = end; settings.range = .custom
        statistics = nil; statisticsError = nil
        refreshStatistics()
    }
    func refreshQuota() {
        guard !isPreview else { return }
        guard !loadingQuota else { pendingQuota = true; return }
        loadingQuota = true; lastQuotaAttempt = Date()
        accountIsVerified = false
        let captured = settings
        let id = UUID(); quotaRequestID = id
        quotaTask = Task { [self] in
            let result: Result<QuotaSnapshot, Error>
            do {
                let snapshot = try await services.readQuota(captured) { [weak self] account in
                    Task { @MainActor in
                        guard let self, self.quotaRequestID == id,
                              captured.codexPath == self.settings.codexPath, captured.codexHome == self.settings.codexHome else { return }
                        if self.account != account { self.quota = nil }
                        self.account = account; self.accountIsVerified = true
                    }
                }
                result = .success(snapshot)
            } catch { result = .failure(error) }
            guard self.quotaRequestID == id, !Task.isCancelled else { return }
            let sameSource = captured.codexPath == self.settings.codexPath && captured.codexHome == self.settings.codexHome
            if sameSource {
                switch result {
                case .success(let snapshot):
                    self.account = snapshot.account ?? CodexAccount(type: "chatgpt", email: snapshot.email, planType: snapshot.response.bucket?.planType)
                    self.accountIsVerified = true
                    self.quota = snapshot; self.quotaError = nil
                case .failure(let error):
                    // Keep the last snapshot for context, but never advertise it as a live value.
                    self.quotaError = error.localizedDescription
                }
            }
            self.loadingQuota = false; self.now = Date()
            if self.pendingQuota || !sameSource { self.pendingQuota = false; self.refreshQuota() }
        }
    }
    func refreshStatistics() {
        guard !isPreview else { return }
        updateStatisticsSource()
        guard !loadingStatistics else { pendingStatistics = true; return }
        let captured = settings
        let range: UsageRange
        do { range = try captured.resolvedRange() }
        catch { statisticsError = error.localizedDescription; return }
        loadingStatistics = true; lastStatisticsAttempt = Date()
        let id = UUID(); statisticsRequestID = id
        statisticsTask = Task {
            let result: Result<UsageSummary, Error>
            do { result = .success(try await services.readStatistics(captured, range)) }
            catch { result = .failure(error) }
            guard self.statisticsRequestID == id, !Task.isCancelled else { return }
            let sameRange = captured.databasePath == self.settings.databasePath && captured.codexHome == self.settings.codexHome
                && captured.range == self.settings.range && captured.customStart == self.settings.customStart
                && captured.customEnd == self.settings.customEnd
                && !captured.range.needsDayRolloverRefresh(queriedRange: range, now: Date())
            if sameRange {
                switch result {
                case .success(let summary): self.statistics = summary; self.statisticsError = nil
                case .failure(let error): self.statisticsError = error.localizedDescription
                }
            }
            self.loadingStatistics = false; self.now = Date()
            if self.pendingStatistics || !sameRange { self.pendingStatistics = false; self.refreshStatistics() }
        }
    }
    private func updateStatisticsSource() {
        guard !isPreview else { return }
        let running = StatisticsSourceController.isRunning
        if running != statisticsSourceRunning { statisticsSourceRunning = running }
        if running { statisticsSourceError = nil }
        else if settings.automaticallyStartCCSwitch {
            statisticsSource.open(activate: false) { [weak self] error in
                guard let self else { return }
                self.statisticsSourceError = error
                self.statisticsSourceRunning = StatisticsSourceController.isRunning
                if error == nil { self.refreshStatistics() }
            }
        }
    }
    func openStatisticsSource() {
        statisticsSource.open(activate: true) { [weak self] error in
            guard let self else { return }
            self.statisticsSourceError = error
            self.statisticsSourceRunning = StatisticsSourceController.isRunning
            if error == nil { self.refreshStatistics() }
        }
    }
    var statisticsSyncState: StatisticsSyncState {
        guard !isPreview else { return previewSyncState }
        guard let statistics, let range = try? settings.resolvedRange(now: now) else {
            return statisticsSourceRunning ? .waitingForSync : .sourceNotRunning
        }
        return .evaluate(summary: statistics, range: range, sourceIsRunning: statisticsSourceRunning, now: now)
    }
    var statisticsHasUnconfirmedZero: Bool {
        statisticsSyncState != .current && statistics?.totalRequests == 0
    }
    var quotaIsStale: Bool {
        if quotaError != nil { return true }
        guard let quota else { return true }
        if let date = quota.preferredWindow?.resetDate, date <= now { return true }
        return now.timeIntervalSince(quota.queriedAt) > max(settings.quotaInterval * 2, 600)
    }
    func menuPresentation(for configuration: AppSettings) -> MenuPresentation {
        let sameQuotaSource = configuration.codexPath == settings.codexPath && configuration.codexHome == settings.codexHome
        let sameStatisticsRange = configuration.databasePath == settings.databasePath && configuration.codexHome == settings.codexHome
            && configuration.range == settings.range && configuration.customStart == settings.customStart
            && configuration.customEnd == settings.customEnd
        return MenuDisplay.presentation(settings: configuration, quota: sameQuotaSource ? quota : nil,
                          statistics: sameStatisticsRange ? statistics : nil, now: now,
                          quotaIsStale: quotaIsStale, loadingQuota: loadingQuota,
                          loadingStatistics: loadingStatistics && sameStatisticsRange,
                          statisticsFailed: sameStatisticsRange && statisticsError != nil,
                          statisticsSyncState: statisticsSyncState)
    }
    static func previewModel(unsynced: Bool = false) -> AppModel {
        let model = AppModel(preview: true, previewSyncState: unsynced ? .sourceNotRunning : .current)
        let reset = Date().addingTimeInterval(6 * 86400 + 18 * 3600).timeIntervalSince1970
        let expiry = Date().addingTimeInterval(15 * 86400).timeIntervalSince1970
        let data = """
        {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":\(reset)},"credits":{"hasCredits":true,"unlimited":false,"balance":"62197.23"},"planType":"pro"},"rateLimitResetCredits":{"availableCount":2,"credits":[{"status":"available","expiresAt":\(expiry)}]}}
        """.data(using: .utf8)!
        model.quota = QuotaSnapshot(response: try! JSONDecoder().decode(RateLimitsResponse.self, from: data))
        model.account = CodexAccount(type: "chatgpt", email: "you@example.com", planType: "pro")
        model.accountIsVerified = true
        var summary = UsageSummary()
        summary.totalRequests = 5576; summary.totalCost = 177.307633
        summary.freshInput = 22820787; summary.output = 2193491; summary.cacheRead = 1045719680
        summary.lastSyncedAt = Date().addingTimeInterval(-40); summary.latestRecordAt = Date().addingTimeInterval(-70)
        model.statistics = summary
        if unsynced {
            var empty = UsageSummary()
            empty.lastSyncedAt = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-3600)
            empty.latestRecordAt = empty.lastSyncedAt
            model.statistics = empty
            model.statisticsSourceRunning = false
            model.settings.menuMetrics = [.quotaUsed, .tokens]
        }
        let demoNews = """
        {"schemaVersion":1,"timezone":"Asia/Shanghai","checkedAt":"2026-10-15T20:30:00+08:00","historyFrom":"2026-10-08T00:00:00+08:00",
         "events":[
          {"id":"demo-announcement","type":"direct_reset","displayLabel":"额度重置","status":"announced","title":"示例：额度重置预告","scope":"付费用户",
           "createdAt":"2026-10-15T19:00:00+08:00","updatedAt":"2026-10-15T19:00:00+08:00",
           "estimate":{"from":"2026-10-15T21:00:00+08:00","through":"2026-10-15T23:00:00+08:00","label":"北京时间 21:00–23:00"},
           "posts":[{"id":"demo-post","publishedAt":"2026-10-15T19:00:00+08:00","stage":"预告","url":"https://aihot.news/codex-reset"}],"url":"https://aihot.news/codex-reset"},
          {"id":"demo-confirmed","type":"reset_credit","displayLabel":"重置卡发放","status":"confirmed","title":"示例：重置卡已发放","scope":"所有付费账户",
           "createdAt":"2026-10-15T12:00:00+08:00","updatedAt":"2026-10-15T13:00:00+08:00","confirmedAt":"2026-10-15T13:00:00+08:00","confirmationBasis":"source_post",
           "posts":[],"url":"https://aihot.news/codex-reset"}],"activities":[],"monitor":{"status":"healthy"}}
        """.data(using: .utf8)!
        var demo = try! ResetNewsFeed.decode(demoNews)
        demo.checkedAt = Date()
        var empty = demo; empty.events = []
        model.newsInbox.receive(empty, etag: nil)
        model.newsInbox.receive(demo, etag: nil)
        return model
    }
}
