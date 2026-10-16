import SwiftUI
import UsageCore

struct ResetNewsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.appPalette) private var style

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tibo 重置动态").font(.system(size: 14, weight: .semibold))
                        Text(model.isPreview ? "示例数据 · 北京时间 UTC+8" : "AIHOT 整理 · 北京时间 UTC+8")
                            .font(.system(size: 11)).foregroundStyle(style.secondary)
                    }
                    Spacer()
                    Link("来源网页 ↗", destination: ResetNewsSource.pageURL).font(.system(size: 11))
                }
                if !model.settings.resetNewsEnabled {
                    notice("已暂停获取重置动态，可在设置中重新开启。", symbol: "pause.circle")
                    Button("打开设置", action: model.showSettings).controlSize(.small)
                }
                if let error = model.newsInbox.lastError {
                    notice(error + (model.newsInbox.feed == nil ? "" : " 下方为上次成功获取的内容。"), symbol: "wifi.exclamationmark")
                }
                if let feed = model.newsInbox.feed {
                    monitor(feed)
                    let pending = feed.sortedEvents.filter { !$0.isConfirmed }
                    if pending.isEmpty {
                        Label("当前没有等待生效的重置预告", systemImage: "checkmark.circle")
                            .font(.system(size: 11)).foregroundStyle(style.secondary)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(style.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        sectionTitle("预告与待确认", count: pending.count)
                        ForEach(pending) { eventCard($0) }
                    }
                    if !feed.withdrawals.isEmpty {
                        sectionTitle("公告撤回", count: feed.withdrawals.count)
                        ForEach(feed.withdrawals) { withdrawal in
                            VStack(alignment: .leading, spacing: 8) {
                                Label("相关重置公告已撤回", systemImage: "arrow.uturn.backward.circle")
                                    .font(.system(size: 12, weight: .medium))
                                Text(ResetNewsSource.dateText(withdrawal.publishedAt)).font(.caption).foregroundStyle(style.secondary)
                                if let url = ResetNewsSource.safeURL(withdrawal.url) { Link("查看撤回原帖 ↗", destination: url).font(.caption) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                                .background(style.card, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    let confirmed = feed.sortedEvents.filter(\.isConfirmed)
                    if !confirmed.isEmpty {
                        sectionTitle("最近已确认", count: confirmed.count)
                        ForEach(confirmed) { eventCard($0) }
                    }
                    if feed.events.isEmpty && feed.withdrawals.isEmpty {
                        Text("近期暂无重置或重置卡发放记录。")
                            .font(.callout).foregroundStyle(style.secondary).padding(.vertical, 12)
                    }
                    Text("展示近期更新和仍待生效的预告。确认帖时间不等于精确到账时间；预计窗口不是到账确认。个人额度请查看“概览”。")
                        .font(.system(size: 11)).foregroundStyle(style.secondary).fixedSize(horizontal: false, vertical: true)
                } else if model.loadingNews {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在获取重置动态…").font(.callout).foregroundStyle(style.secondary)
                    }.padding(.vertical, 24)
                } else if model.settings.resetNewsEnabled {
                    Text("还没有可显示的重置动态。").font(.callout).foregroundStyle(style.secondary).padding(.vertical, 12)
                }
                HStack {
                    Text("非 OpenAI 官方页面").font(.system(size: 11)).foregroundStyle(style.secondary)
                    Spacer()
                    Button("检查更新") { model.refreshNews() }.controlSize(.small).disabled(!model.canRefreshNews)
                }
                if let date = model.newsInbox.nextAllowedFetchAt, date > model.now, model.settings.resetNewsEnabled {
                    Text("下次可检查 " + ResetNewsSource.dateText(date))
                        .font(.system(size: 11)).foregroundStyle(style.secondary)
                }
            }.padding(18)
        }.scrollIndicators(.hidden)
    }

    private func monitor(_ feed: ResetNewsFeed) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let status = feed.monitor?.statusText ?? "来源监控状态未知"
            Label(status, systemImage: feed.monitor?.status == "healthy" ? "dot.radiowaves.left.and.right" : "clock")
                .foregroundStyle(feed.monitor?.status == "healthy" ? style.accent : .orange)
            if let date = feed.checkedAt {
                Text("来源核对时间 " + ResetNewsSource.dateText(date))
                if model.now.timeIntervalSince(date) > 1800 { Text("来源核对已超过 30 分钟").foregroundStyle(.orange) }
            } else { Text("来源未提供核对时间") }
            if let date = model.newsInbox.receivedAt { Text("本机获取 " + ResetNewsSource.dateText(date)) }
        }.font(.system(size: 11)).foregroundStyle(style.secondary)
    }
    private func eventCard(_ event: ResetNewsEvent) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                Text(event.kindText).font(.system(size: 11, weight: .medium)).foregroundStyle(style.secondary)
                Spacer()
                Text(event.statusText).font(.system(size: 11, weight: .medium))
                    .foregroundStyle(event.isConfirmed ? style.accent : .orange)
                    .multilineTextAlignment(.trailing)
            }
            Text(String(event.title.prefix(200))).font(.system(size: 13, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.timeText)
                Text("适用范围：" + event.scopeText)
                if let products = event.presentation?.productsZh, !products.isEmpty { Text("适用产品：" + String(products.prefix(120))) }
                if let estimate = event.estimateText { Text(estimate).foregroundStyle(.orange) }
            }.font(.system(size: 11)).foregroundStyle(style.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if let url = ResetNewsSource.safeURL(event.url) { Link("AIHOT 详情 ↗", destination: url) }
                if let post = event.posts.sorted(by: { $0.publishedAt > $1.publishedAt }).first,
                   let url = ResetNewsSource.safeURL(post.url) { Link("查看原帖 ↗", destination: url) }
            }.font(.system(size: 11))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(style.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(style.hairline, lineWidth: 1))
    }
    private func notice(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(style.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }
    private func sectionTitle(_ text: String, count: Int) -> some View {
        HStack {
            Text(text).font(.system(size: 11, weight: .semibold))
            Spacer()
            Text(String(count) + " 条").font(.system(size: 11))
        }.foregroundStyle(style.secondary)
    }
}
