import SwiftUI
import UsageCore

/// 概览与分析共用来源、范围和错误状态；分析不发起第二套查询。
struct StatisticsSection: View {
    @ObservedObject var model: AppModel
    let analysis: Bool
    @Binding var customStart: Date
    @Binding var customEnd: Date
    private var rangeError: String? { UsageRange.validationMessage(start: customStart, end: customEnd) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                panelSectionLabel(analysis ? "Token 构成" : "用量统计", symbol: analysis ? "chart.bar.xaxis" : "chart.bar")
                Spacer()
                Picker("统计范围", selection: Binding(get: { model.settings.range }, set: { model.setRange($0) })) {
                    ForEach(RangePreset.allCases) { Text($0.title).tag($0) }
                }.labelsHidden().fixedSize().controlSize(.small).accessibilityLabel("统计时间范围")
            }
            if model.settings.range == .custom { customRange }
            if let error = model.statisticsError {
                PanelMessage(text: error, retry: model.refreshStatistics, settings: model.showSettings)
            }
            if let stats = model.statistics {
                sourceNotice
                let unavailable = model.statisticsHasUnconfirmedZero || model.statisticsError != nil
                if analysis {
                    if unavailable {
                        Label(model.statisticsError != nil ? "统计暂不可用，重新读取后查看构成。" : "等待 CC Switch 同步后查看构成。", systemImage: "chart.bar.xaxis")
                            .font(.callout).foregroundStyle(.secondary).padding(.vertical, 16)
                    } else { tokenBreakdown(stats) }
                } else { metrics(stats, unavailable: unavailable) }
                if stats.totalRequests == 0 && !unavailable && !analysis {
                    Text("此时段暂无用量记录").font(.caption).foregroundStyle(.secondary)
                }
                if stats.archiveBoundaryOmitted {
                    Label("范围边界含已归档数据，仅计入完整日期。", systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                // 归属与异常必须常显，只有正常来源的时间细节可折叠。
                Text("本机 Codex 记录 · CC Switch")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("本机历史不保证按 ChatGPT 账户拆分，与概览的当前账户额度独立。")
                if analysis { Text("本机历史不保证属于当前登录账户。").font(.system(size: 11)).foregroundStyle(.secondary) }
                DisclosureGroup("来源详情") {
                    VStack(alignment: .leading, spacing: 5) {
                        if let range = stats.queriedRange { Text("已查询 " + fullDate(range.start) + " – " + fullDate(range.end)) }
                        if let date = stats.lastSyncedAt {
                            Text("会话同步 " + fullDate(date))
                                .foregroundStyle(model.statisticsSyncState == .current ? Color.secondary : Color.orange)
                        } else { Text("会话同步时间未知") }
                        if let date = stats.latestRecordAt { Text("最近请求 " + fullDate(date)) }
                        Text("本次读取 " + shortTime(stats.readAt) + " · 费用来自 CC Switch")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            } else if model.loadingStatistics {
                HStack { ProgressView().controlSize(.small); Text("正在读取 CC Switch…") }.font(.callout).foregroundStyle(.secondary).padding(.vertical, 12)
            }
        }
    }

    private var customRange: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("开始时间", selection: $customStart, displayedComponents: [.date, .hourAndMinute])
            DatePicker("结束时间", selection: $customEnd, displayedComponents: [.date, .hourAndMinute])
            if let error = rangeError { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            HStack { Spacer(); Button("应用范围") { model.setCustomRange(start: customStart, end: customEnd) }.disabled(rangeError != nil).controlSize(.small) }
            Text("编辑后点击“应用范围”。下方数据仍对应已应用的时段。")
                .foregroundStyle(.secondary)
            if let range = model.statistics?.queriedRange {
                Text("已应用 " + fullDate(range.start) + " – " + fullDate(range.end)).foregroundStyle(.secondary)
            }
        }.font(.system(size: 11)).padding(10).panelCard()
    }

    @ViewBuilder private var sourceNotice: some View {
        if let notice = model.statisticsSourceError ?? model.statisticsSyncState.message {
            VStack(alignment: .leading, spacing: 7) {
                Label(notice, systemImage: "exclamationmark.circle")
                Text(model.statisticsHasUnconfirmedZero ? "尚未同步到所选时段的数据，暂不显示用量。" : "以下为最近一次同步的统计结果。")
                HStack {
                    Button(model.statisticsSourceRunning ? "查看 CC Switch" : "打开 CC Switch 同步", action: model.openStatisticsSource)
                    Button("重新读取", action: model.refreshStatistics)
                }.controlSize(.small)
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private func metrics(_ stats: UsageSummary, unavailable: Bool) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            metric("统计费用", value: unavailable ? "—" : DisplayFormat.money(stats.totalCost), symbol: "dollarsign.circle", hint: "CC Switch 已存费用，不代表订阅实付或 Credits 扣款。")
            metric("Token 用量", value: unavailable ? "—" : DisplayFormat.compact(Double(stats.realTotalTokens)), symbol: "square.stack.3d.up", hint: "包含缓存命中；分析页可查看四类构成。")
            metric("总请求数", value: unavailable ? "—" : DisplayFormat.number(Double(stats.totalRequests), digits: 0), symbol: "arrow.up.arrow.down", hint: "按 CC Switch 有效记录口径统计。")
            metric("缓存命中率", value: unavailable || stats.totalRequests == 0 ? "—" : DisplayFormat.number(stats.cacheHitRate * 100, digits: 1) + "%", symbol: "bolt", hint: "缓存命中 Tokens / 全部输入 Tokens（含缓存），不包含输出。")
        }
    }

    private func metric(_ label: String, value: String, symbol: String, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(label, systemImage: symbol).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.65)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(12).panelCard()
            .help(hint).accessibilityElement(children: .combine)
    }

    private func tokenBreakdown(_ stats: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("全部 Token").font(.system(size: 11)).foregroundStyle(.secondary)
                Text(DisplayFormat.compact(Double(stats.realTotalTokens)))
                    .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                    .help(DisplayFormat.number(Double(stats.realTotalTokens), digits: 0) + " Tokens")
            }.accessibilityElement(children: .combine)
            if stats.realTotalTokens > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(stats.tokenBreakdown) { item in
                            tokenColor(item.kind).frame(width: geometry.size.width * max(0, min(1, item.fraction ?? 0)))
                        }
                    }.clipShape(Capsule())
                }.frame(height: 10).accessibilityHidden(true)
            } else { Text("此时段暂无 Token 记录").font(.callout).foregroundStyle(.secondary) }
            VStack(spacing: 12) {
                ForEach(stats.tokenBreakdown) { item in
                    let share = item.fraction.map { DisplayFormat.number($0 * 100, digits: 1) + "%" } ?? "—"
                    HStack(spacing: 9) {
                        Circle().fill(tokenColor(item.kind)).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(item.kind.title).font(.system(size: 12))
                        Spacer()
                        Text(DisplayFormat.compact(Double(item.tokens))).font(.system(size: 13, weight: .medium)).monospacedDigit()
                        Text(share).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary).frame(width: 48, alignment: .trailing)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel(item.kind.title + "，" + DisplayFormat.number(Double(item.tokens), digits: 0) + " Tokens，占全部 Token " + share)
                        .help(DisplayFormat.number(Double(item.tokens), digits: 0) + " Tokens")
                }
            }
            Text("份额按全部 Token 计算，包含输出；概览中的缓存命中率仅按输入计算。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).panelCard()
    }

    private func tokenColor(_ kind: TokenKind) -> Color {
        switch kind {
        case .freshInput: return .blue
        case .output: return .purple
        case .cacheWrite: return .orange
        case .cacheRead: return AppStyle.accent
        }
    }
}
