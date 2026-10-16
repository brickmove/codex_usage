import SwiftUI
import AppKit
import UsageCore

enum SettingsCategory: String, CaseIterable, Identifiable {
    case menu, data, news
    var id: String { rawValue }
    var title: String {
        switch self {
        case .menu: return "菜单栏"
        case .data: return "数据与刷新"
        case .news: return "重置动态"
        }
    }
}

/// 分类仅切换可见内容，所有编辑共用一份草稿，取消不会调用 apply。
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var draft: AppSettings
    @State private var category: SettingsCategory
    let close: () -> Void
    init(model: AppModel, initialCategory: SettingsCategory = .menu, close: @escaping () -> Void) {
        self.model = model; self.close = close
        _draft = State(initialValue: model.settings)
        _category = State(initialValue: initialCategory)
    }
    private var rangeError: String? {
        draft.range == .custom ? UsageRange.validationMessage(start: draft.customStart, end: draft.customEnd) : nil
    }
    var body: some View {
        VStack(spacing: 0) {
            Picker("设置分类", selection: $category) {
                ForEach(SettingsCategory.allCases) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().padding(16)
            if category == .menu { menuPreview }
            Divider()
            Form {
                switch category {
                case .menu:
                    Section("菜单栏显示") {
                        ForEach(orderedMetrics) { metric in
                            menuMetricRow(metric)
                        }
                        HStack {
                            Button("恢复默认显示") { draft.menuMetrics = MenuMetric.defaults }
                            Button("仅显示图标") { draft.menuMetrics = [] }
                        }.controlSize(.small)
                        Text("菜单栏以图标和数值显示，用上下箭头调整顺序。悬停可查看指标名称与时间范围。")
                            .font(.caption).foregroundStyle(.secondary)
                }
                case .data:
                    Section("自动刷新") {
                        Toggle("自动在后台启动 CC Switch", isOn: $draft.automaticallyStartCCSwitch)
                        Text("用量由 CC Switch 同步。开启后，CC Switch 未运行时会在后台启动；关闭本工具不会退出 CC Switch。")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("后台同步可能延迟约 10 分钟。需要更快更新时，请打开 CC Switch 的用量统计页并启用自动扫描。")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("账户额度", selection: $draft.quotaInterval) {
                            Text("手动刷新").tag(TimeInterval(0))
                            Text("每 1 分钟").tag(TimeInterval(60))
                            Text("每 5 分钟（默认）").tag(TimeInterval(300))
                            Text("每 10 分钟").tag(TimeInterval(600))
                            Text("每 15 分钟").tag(TimeInterval(900))
                        }
                        Picker("本地统计", selection: $draft.statisticsInterval) {
                            Text("手动刷新").tag(TimeInterval(0))
                            Text("每 15 秒").tag(TimeInterval(15))
                            Text("每 30 秒（默认）").tag(TimeInterval(30))
                            Text("每 1 分钟").tag(TimeInterval(60))
                            Text("每 5 分钟").tag(TimeInterval(300))
                        }
                        Text("启动和唤醒时刷新。倒计时在本地更新，不会额外发送查询。")
                            .font(.caption).foregroundStyle(.secondary)
                }
                Section("统计范围") {
                    Picker("统计时间范围", selection: $draft.range) {
                        ForEach(RangePreset.allCases) { Text($0.title).tag($0) }
                    }
                    if draft.range == .custom {
                        DatePicker("开始时间", selection: $draft.customStart, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("结束时间", selection: $draft.customEnd, displayedComponents: [.date, .hourAndMinute])
                        if let error = rangeError { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
                    }
                }
                Section("数据来源") {
                    pathField("CC Switch 数据库", text: $draft.databasePath, placeholder: "~/.cc-switch/cc-switch.db", directory: false)
                    pathField("Codex CLI", text: $draft.codexPath, placeholder: "自动查找 codex", directory: false)
                    pathField("Codex 配置目录", text: $draft.codexHome, placeholder: "默认 CODEX_HOME 或 ~/.codex", directory: true)
                    Text("额度使用所选 Codex 配置中的登录账户。统计仅只读 CC Switch 的 Codex 记录，金额沿用已存费用。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("CC Switch 停止同步时，统计数据也会停止更新。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                case .news:
                    Section("重置动态") {
                        Toggle("获取 AIHOT 重置动态", isOn: $draft.resetNewsEnabled)
                        Toggle("有新动态时在菜单栏提示", isOn: $draft.showResetNewsIndicator)
                            .disabled(!draft.resetNewsEnabled)
                        Picker("检查间隔", selection: $draft.resetNewsInterval) {
                            Text("手动检查").tag(TimeInterval(0))
                            Text("每 10 分钟（默认）").tag(TimeInterval(600))
                            Text("每 30 分钟").tag(TimeInterval(1800))
                            Text("每 1 小时").tag(TimeInterval(3600))
                        }.disabled(!draft.resetNewsEnabled)
                        Text("新公告或实质更新会显示铃铛图标；查看“重置动态”后恢复。首次加载历史记录不提示。最短检查间隔为 10 分钟。")
                            .font(.caption).foregroundStyle(.secondary)
                }
                }
            }.formStyle(.grouped)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                if let error = rangeError {
                    Label(error + " 请在“数据与刷新”中修正。", systemImage: "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
                HStack {
                    Button("恢复全部默认") { draft = AppSettings() }
                    Spacer()
                    Button("取消", action: close).keyboardShortcut(.cancelAction)
                    Button("保存并刷新") { model.apply(draft); close() }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                        .disabled(rangeError != nil)
                }
            }.padding(16)
        }.frame(width: 520, height: 650)
            .background(Color(nsColor: .windowBackgroundColor)).tint(AppStyle.accent)
    }

    private var orderedMetrics: [MenuMetric] {
        draft.menuMetrics + MenuMetric.allCases.filter { !draft.menuMetrics.contains($0) }
    }
    private var menuPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("菜单栏预览").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Text(draft.menuMetrics.isEmpty ? "仅显示图标" : "已选 \(draft.menuMetrics.count) 项")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ScrollView(.horizontal) {
                let presentation = model.menuPresentation(for: draft)
                let indicator = model.newsIndicator(for: draft)
                HStack(spacing: 6) {
                    if indicator || presentation.statisticsNotice != nil || presentation.items.isEmpty {
                        Image(systemName: indicator ? "bell.badge.fill" : presentation.statisticsNotice != nil ? "exclamationmark.circle" : "gauge.with.dots.needle.50percent")
                    }
                    if !presentation.items.isEmpty { MenuBarValuesPreview(items: presentation.items).fixedSize() }
                }.font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 9)
            }.background(AppStyle.card, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("菜单栏预览")
        }.padding(16)
    }
    private func menuMetricRow(_ metric: MenuMetric) -> some View {
        let index = draft.menuMetrics.firstIndex(of: metric)
        return HStack(spacing: 8) {
            Text(index.map { String($0 + 1) } ?? "—")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).frame(width: 16)
                .accessibilityHidden(true)
            Toggle(metric.title, isOn: Binding(
                get: { draft.menuMetrics.contains(metric) },
                set: { draft.setMenuMetric(metric, enabled: $0) }
            )).toggleStyle(.checkbox).font(.system(size: 12))
            Spacer()
            if let index {
                Button { draft.moveMenuMetric(metric, by: -1) } label: {
                    Image(systemName: "chevron.up").frame(width: 22, height: 22)
                }.disabled(index == 0).help("上移" + metric.title).accessibilityLabel("上移" + metric.title)
                Button { draft.moveMenuMetric(metric, by: 1) } label: {
                    Image(systemName: "chevron.down").frame(width: 22, height: 22)
                }.disabled(index == draft.menuMetrics.count - 1).help("下移" + metric.title).accessibilityLabel("下移" + metric.title)
            }
        }.buttonStyle(.borderless)
    }
    private func pathField(_ label: String, text: Binding<String>, placeholder: String, directory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.callout)
            HStack {
                TextField(placeholder, text: text).textFieldStyle(.roundedBorder)
                    .labelsHidden().font(.system(size: 11, design: .monospaced)).accessibilityLabel(label)
                Button("选择…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
                    panel.allowsMultipleSelection = false; panel.prompt = "选择"
                    if panel.runModal() == .OK, let url = panel.url { text.wrappedValue = url.path }
                }.accessibilityLabel("选择" + label)
            }
        }
    }
}
