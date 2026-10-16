import SwiftUI
import AppKit
import UsageCore

enum AppStyle {
    static let accent = Color(red: 0.02, green: 0.52, blue: 0.58)
    static let card = Color(nsColor: .controlBackgroundColor)
    static let hairline = Color.primary.opacity(0.08)
}

/// 短暂查看的面板固定头尾，正文滚动；三个页面共享范围草稿和屏幕限高。
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @State private var customStart = Date()
    @State private var customEnd = Date()

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("面板", selection: $model.selectedTab) {
                Text("概览").tag(PanelTab.usage)
                Text("分析").tag(PanelTab.analysis)
                Text(model.unreadNewsCount > 0 ? "重置动态 · \(model.unreadNewsCount)" : "重置动态").tag(PanelTab.resetNews)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, 16).padding(.bottom, 12)
            Divider()
            if model.selectedTab == .resetNews { ResetNewsView(model: model) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.selectedTab == .usage {
                            accountSection
                            quotaSection
                        }
                        StatisticsSection(model: model, analysis: model.selectedTab == .analysis,
                                          customStart: $customStart, customEnd: $customEnd)
                    }.padding(16)
                }
            }
            Divider()
            footer
        }
        .frame(width: 400, height: model.panelHeight)
        .background(Color(nsColor: .windowBackgroundColor)).tint(AppStyle.accent)
        .onAppear { customStart = model.settings.customStart; customEnd = model.settings.customEnd }
        .onChange(of: model.settings.customStart) { _, value in customStart = value }
        .onChange(of: model.settings.customEnd) { _, value in customEnd = value }
        .onExitCommand { model.dismissPopover() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 21, weight: .medium)).foregroundStyle(AppStyle.accent)
                .frame(width: 34, height: 34).background(AppStyle.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex Usage").font(.system(size: 15, weight: .semibold))
                Text(model.isPreview ? "示例数据" : model.isRecovering ? "正在恢复连接…" : "额度与用量")
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
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var accountSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle").font(.system(size: 24)).foregroundStyle(AppStyle.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.accountIsVerified ? "当前账户" : model.account == nil ? "账户" : "上次识别账户")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Text(model.account?.displayName ?? (model.accountIsVerified ? "Codex 尚未登录" : model.loadingQuota || model.isRecovering ? "正在识别 Codex 账户…" : "暂时无法识别账户"))
                    .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled).help(model.account?.displayName ?? "使用 Codex 已有的登录状态，无需在本应用重新登录。")
            }
            Spacer(minLength: 4)
            if let plan = model.account?.planType ?? model.quota?.response.bucket?.planType {
                Text(plan.uppercased()).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
    }

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                panelSectionLabel("账户额度", symbol: "chart.pie")
                Spacer()
                if let quota = model.quota {
                    Text((model.quotaIsStale ? "待更新 · 上次查询 " : "已更新 ") + shortTime(quota.queriedAt))
                        .font(.system(size: 11)).foregroundStyle(model.quotaIsStale ? Color.orange : Color.secondary)
                }
            }
            if let error = model.quotaError {
                PanelMessage(text: error, retry: model.refreshQuota, settings: model.showSettings)
            } else if let quota = model.quota {
                let account = AccountQuotaPresentation(snapshot: quota, now: model.now, isStale: model.quotaIsStale)
                VStack(spacing: 10) {
                    if let window = quota.preferredWindow {
                        windowView(window)
                        let extra = quota.windows.filter { $0 != window }
                        if !extra.isEmpty {
                            DisclosureGroup("其他额度窗口 · \(extra.count)") {
                                VStack(spacing: 12) {
                                    ForEach(Array(extra.enumerated()), id: \.offset) { _, item in windowView(item) }
                                }.padding(.top, 10)
                            }.font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    } else { Text("此账户未返回额度窗口").font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    Divider()
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Label("Credits", systemImage: "creditcard").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(account.creditsText).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                            if let estimate = account.estimatedValueText {
                                Text(estimate).font(.system(size: 11)).foregroundStyle(.secondary)
                                    .help("按 CC Switch 的换算方式展示：1 Credit = $0.04，不代表实际扣款。")
                            }
                        }.accessibilityElement(children: .combine)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Label("可用重置", systemImage: "arrow.counterclockwise").font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(account.availableResetsText).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                            if let expiry = account.nextExpiryText { Text(expiry).font(.system(size: 11)).foregroundStyle(.secondary) }
                        }.help("可手动重置额度的次数；有效期与额度自动重置时间独立。")
                            .accessibilityElement(children: .combine)
                    }
                    if !model.quotaIsStale && quota.response.ordinaryUsageAllowed == false {
                        Label("当前账户的订阅用量受限，请查看 Codex。", systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(12).panelCard()
            } else {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text("正在查询 Codex 账户额度…").font(.callout).foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
        }
    }

    private func windowView(_ window: RateWindow) -> some View {
        let state = RateWindowPresentation(window: window, now: model.now, quotaIsStale: model.quotaIsStale)
        let color: Color = window.remainingPercent <= 10 ? .red : (window.remainingPercent <= 30 ? .orange : AppStyle.accent)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("剩余").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(state.remainingText).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    if let progress = state.progress { Capsule().fill(color).frame(width: geometry.size.width * progress) }
                }
            }.frame(height: 6).accessibilityHidden(true)
            HStack {
                Text(state.usedText)
                Spacer()
                Text(state.isCurrent ? DisplayFormat.countdown(to: window.resetDate, now: model.now) + (window.resetDate == nil ? "" : "后重置") : "等待重新查询")
            }.font(.system(size: 11)).foregroundStyle(.secondary)
            if state.isCurrent, let date = window.resetDate {
                Text("自动重置 " + fullDate(date)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(state.accessibilitySummary + (state.isCurrent ? "，" + DisplayFormat.countdown(to: window.resetDate, now: model.now) : ""))
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
        }.font(.system(size: 11)).buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 12)
    }
}

extension View {
    func panelCard() -> some View {
        background(AppStyle.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(AppStyle.hairline, lineWidth: 1))
    }
}
func panelSectionLabel(_ title: String, symbol: String) -> some View {
    Label(title, systemImage: symbol).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
}
struct PanelMessage: View {
    let text: String
    let retry: () -> Void
    let settings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "exclamationmark.circle") }
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack { Button("重试", action: retry); Button("设置…", action: settings) }.controlSize(.small)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}
func shortTime(_ date: Date) -> String { date.formatted(.dateTime.hour().minute()) }
func fullDate(_ date: Date) -> String { date.formatted(.dateTime.month().day().hour().minute()) }
@MainActor func openCCSwitch() {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.ccswitch.desktop") else { return }
    NSWorkspace.shared.openApplication(at: url, configuration: .init())
}
