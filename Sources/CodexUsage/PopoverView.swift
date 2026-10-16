import SwiftUI
import AppKit
import UsageCore

enum AppStyle {
    static let accent = Color(red: 0.02, green: 0.52, blue: 0.58)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.08)
}

struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var customStart = Date()
    @State private var customEnd = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("面板", selection: $model.selectedTab) {
                Text("用量").tag(PanelTab.usage)
                Text(model.unreadNewsCount > 0 ? "重置动态 · \(model.unreadNewsCount)" : "重置动态").tag(PanelTab.resetNews)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 18).padding(.bottom, 12)
            Divider()
            if model.selectedTab == .resetNews { ResetNewsView(model: model) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        accountSection
                        quotaSection
                        statisticsSection
                    }.padding(18)
                }.scrollIndicators(.hidden)
            }
            Divider()
            footer
        }
        .frame(width: 400, height: model.selectedTab == .usage && model.settings.range == .custom ? 750 : 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(AppStyle.accent)
        .onAppear { customStart = model.settings.customStart; customEnd = model.settings.customEnd }
        .onExitCommand { model.dismissPopover() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 21, weight: .medium)).foregroundStyle(AppStyle.accent)
                .frame(width: 34, height: 34).background(AppStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Usage").font(.system(size: 15, weight: .semibold))
                Text(model.isRecovering ? "正在恢复连接…" : "额度与用量")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { if model.selectedTab == .resetNews { model.refreshNews() } else { model.refreshAll() } } label: {
                if model.selectedTab == .resetNews ? model.loadingNews : (model.loadingQuota || model.loadingStatistics) {
                    ProgressView().controlSize(.small).frame(width: 16, height: 16)
                } else { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
            }.buttonStyle(.borderless)
                .help(model.selectedTab == .resetNews ? "检查重置动态（最短间隔 10 分钟） ⌘R" : "刷新额度与统计 ⌘R")
                .accessibilityLabel(model.selectedTab == .resetNews ? "检查重置动态" : "刷新额度与统计")
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.selectedTab == .resetNews ? !model.canRefreshNews : (model.loadingQuota && model.loadingStatistics))
        }.padding(.horizontal, 18).padding(.vertical, 14)
    }

    private var accountSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle").font(.system(size: 24)).foregroundStyle(AppStyle.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.accountIsVerified ? "当前账户" : model.account == nil ? "账户" : "上次识别账户")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text(model.account?.displayName ?? (model.accountIsVerified ? "Codex 尚未登录" : model.loadingQuota || model.isRecovering ? "正在识别 Codex 账户…" : "暂时无法识别账户"))
                    .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled).help(model.account?.displayName ?? "使用 Codex 已有的登录状态，无需在本应用重新登录。")
            }
            Spacer(minLength: 4)
            if let plan = model.account?.planType ?? model.quota?.response.bucket?.planType {
                Text(plan.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("账户额度", symbol: "chart.pie")
                Spacer()
                if model.quota != nil {
                    Text(model.quotaIsStale ? "待更新" : "已更新 " + shortTime(model.quota!.queriedAt))
                        .font(.system(size: 10)).foregroundStyle(model.quotaIsStale ? Color.orange : Color.secondary)
                }
            }
            if let error = model.quotaError {
                message(error, symbol: "exclamationmark.circle", action: model.refreshQuota)
            } else if let quota = model.quota {
                VStack(spacing: 14) {
                    if let window = quota.preferredWindow {
                        windowView(window)
                        ForEach(Array(quota.windows.filter { $0 != window }.enumerated()), id: \.offset) { _, extra in
                            windowView(extra)
                        }
                    } else { Text("此账户未返回额度窗口").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    Divider()
                    HStack(alignment: .firstTextBaseline) {
                        Label("Credits", systemImage: "creditcard").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(creditsText).font(.system(size: 17, weight: .semibold, design: .rounded)).monospacedDigit()
                            if let balance = quota.response.bucket?.credits?.balance, quota.response.bucket?.credits?.unlimited != true {
                                Text("约 $" + String(Int((balance * 0.04).rounded())))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                                    .help("按 CC Switch 的换算方式展示：1 Credit = $0.04。")
                            }
                        }
                    }
                    HStack(alignment: .firstTextBaseline) {
                        Label("可用重置", systemImage: "arrow.counterclockwise").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(quota.response.rateLimitResetCredits.map { "\($0.availableCount) 次" } ?? "未提供")
                                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                            if let expiry = quota.response.rateLimitResetCredits?.nextExpiry(now: model.now) {
                                Text("已知最早到期 " + expiry.formatted(.dateTime.month().day()))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                        }
                    }.help("可手动重置额度的次数；有效期与额度自动重置时间独立。")
                    if quota.response.ordinaryUsageAllowed == false {
                        Label("当前账户的订阅用量受限，请查看 Codex。", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(16).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppStyle.hairline, lineWidth: 1))
            } else {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("正在查询 Codex 账户额度…").font(.callout).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        }
    }

    private func windowView(_ window: RateWindow) -> some View {
        let expired = window.resetDate.map { $0 <= model.now } ?? false
        let color: Color = window.remainingPercent <= 10 ? .red : (window.remainingPercent <= 30 ? .orange : AppStyle.accent)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("剩余").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(expired || model.quotaIsStale ? "—" : "\(Int(window.remainingPercent))%")
                    .font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule().fill(color).frame(width: geometry.size.width * window.remainingPercent / 100)
                }
            }.frame(height: 6)
                .accessibilityLabel("\(window.title)剩余 \(Int(window.remainingPercent))%")
            HStack {
                Text("已用 \(DisplayFormat.number(window.usedPercent, digits: 0))%")
                Spacer()
                Text(DisplayFormat.countdown(to: window.resetDate, now: model.now) + (expired || window.resetDate == nil ? "" : "后重置"))
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            if let date = window.resetDate {
                Text("自动重置 " + fullDate(date)).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var creditsText: String {
        if model.quota?.response.bucket?.credits?.unlimited == true { return "不限量" }
        if let balance = model.quota?.response.bucket?.credits?.balance { return DisplayFormat.number(balance) }
        return "未提供"
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("用量统计", symbol: "chart.bar")
                Spacer()
                Picker("统计范围", selection: Binding(get: { model.settings.range }, set: { model.setRange($0) })) {
                    ForEach(RangePreset.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize().controlSize(.small).accessibilityLabel("统计时间范围")
            }
            if model.settings.range == .custom {
                VStack(spacing: 8) {
                    DatePicker("开始时间", selection: $customStart, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("结束时间", selection: $customEnd, displayedComponents: [.date, .hourAndMinute])
                    HStack { Spacer(); Button("应用范围") { model.setCustomRange(start: customStart, end: customEnd) }.controlSize(.small) }
                }.font(.system(size: 11)).padding(10).background(AppStyle.card, in: RoundedRectangle(cornerRadius: 10))
            }
            if let error = model.statisticsError { message(error, symbol: "exclamationmark.circle", action: model.refreshStatistics) }
            if let stats = model.statistics {
                if let notice = model.statisticsSourceError ?? model.statisticsSyncState.message {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(notice, systemImage: "exclamationmark.circle")
                        Text(model.statisticsHasUnconfirmedZero
                             ? "尚未同步到所选时段的数据，暂不显示用量。"
                             : "以下为最近一次同步的统计结果。")
                        HStack {
                            Button(model.statisticsSourceRunning ? "查看 CC Switch" : "打开 CC Switch 同步", action: model.openStatisticsSource)
                            Button("重新读取", action: model.refreshStatistics)
                        }.controlSize(.small)
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                }
                let unconfirmed = model.statisticsHasUnconfirmedZero
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    metric("统计费用", value: unconfirmed ? "—" : DisplayFormat.money(stats.totalCost), symbol: "dollarsign.circle", hint: "CC Switch 统计费用，不代表订阅实付金额或 Credits 扣款。")
                    metric("Token 用量", value: unconfirmed ? "—" : DisplayFormat.compact(Double(stats.realTotalTokens)), symbol: "square.stack.3d.up", hint: unconfirmed ? "等待来源同步" : DisplayFormat.number(Double(stats.realTotalTokens), digits: 0) + " Tokens（包含缓存命中）")
                    metric("总请求数", value: unconfirmed ? "—" : DisplayFormat.number(Double(stats.totalRequests), digits: 0), symbol: "arrow.up.arrow.down", hint: "按 CC Switch 有效记录口径统计。")
                    metric("缓存命中率", value: unconfirmed || stats.totalRequests == 0 ? "—" : DisplayFormat.number(stats.cacheHitRate * 100, digits: 1) + "%", symbol: "bolt", hint: "缓存命中 Tokens / 全部输入 Tokens（含缓存）")
                }.opacity(model.statisticsError == nil ? 1 : 0.5)
                if stats.totalRequests == 0 && !unconfirmed { Text("此时段暂无用量记录").font(.caption).foregroundStyle(.secondary) }
                if stats.archiveBoundaryOmitted {
                    Label("范围边界含已归档数据，仅计入完整日期。", systemImage: "info.circle")
                        .font(.system(size: 10)).foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex · CC Switch 本机记录 · " + model.settings.range.title)
                    if let date = stats.lastSyncedAt {
                        Text("会话同步 " + fullDate(date)).foregroundStyle(model.now.timeIntervalSince(date) > 600 ? .orange : .secondary)
                    } else { Text("会话同步时间未知") }
                    if let date = stats.latestRecordAt { Text("最近请求 " + fullDate(date)) }
                    Text("本次读取 " + shortTime(stats.readAt) + " · 费用来自 CC Switch")
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            } else if model.loadingStatistics {
                HStack { ProgressView().controlSize(.small); Text("正在读取 CC Switch…").font(.callout).foregroundStyle(.secondary) }.padding(.vertical, 12)
            }
        }
    }

    private func metric(_ label: String, value: String, symbol: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(label, systemImage: symbol).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(13)
            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppStyle.hairline, lineWidth: 1))
            .help(hint).accessibilityElement(children: .combine)
    }
    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
    private func message(_ text: String, symbol: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: symbol) }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("重试", action: action)
                Button("设置…", action: model.showSettings)
            }.controlSize(.small)
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
    private var footer: some View {
        HStack {
            Button { model.showSettings() } label: { Label("设置", systemImage: "gearshape") }
                .keyboardShortcut(",", modifiers: .command)
            Spacer()
            Button(model.selectedTab == .resetNews ? "打开 AIHOT" : "打开 CC Switch") {
                if model.selectedTab == .resetNews { NSWorkspace.shared.open(ResetNewsSource.pageURL) }
                else { openCCSwitch() }
            }
            Divider().frame(height: 12)
            Button("退出") { NSApp.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
        }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 12)
    }
}

func shortTime(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
func fullDate(_ date: Date) -> String { date.formatted(.dateTime.month().day().hour().minute()) }
@MainActor func openCCSwitch() {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ccswitch.desktop") else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init())
}
