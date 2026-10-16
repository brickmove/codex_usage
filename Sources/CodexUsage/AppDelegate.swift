import AppKit
import SwiftUI
import Combine
import Network
import UsageCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let model: AppModel
    init(model: AppModel) { self.model = model; super.init() }
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var subscription: AnyCancellable?
    private var workspaceObservers: [NSObjectProtocol] = []
    private let networkMonitor = NWPathMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "Codex 用量")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            button.target = self; button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient; popover.animates = true; popover.delegate = self
        let hosting = NSHostingController(rootView: PopoverView(model: model))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        model.showSettings = { [weak self] in self?.openSettings() }
        model.dismissPopover = { [weak self] in self?.popover.performClose(nil) }
        subscription = model.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.updateStatus()
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.model.recoverAfterWake() }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.model.prepareForSleep() }
        })
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.model.networkBecameAvailable() }
        }
        networkMonitor.start(queue: DispatchQueue(label: "local.codexusage.network"))
        updateStatus(); model.start()
        if CommandLine.arguments.contains("--settings") || Bundle.main.object(forInfoDictionaryKey: "CodexUsageStartInSettings") as? Bool == true {
            openSettings()
            return
        }
        if model.isPreview || !UserDefaults.standard.bool(forKey: "didShowWelcome") {
            if !model.isPreview { UserDefaults.standard.set(true, forKey: "didShowWelcome") }
            DispatchQueue.main.async { [weak self] in self?.showPopover() }
        }
    }
    private func updateStatus() {
        let presentation = model.menuPresentation(for: model.settings)
        let title = presentation.summary
        let indicator = model.showNewsIndicator
        let image = MenuBarIcon.image(settings: model.settings, unread: indicator,
                                      notice: presentation.statisticsNotice, hasMetrics: !presentation.items.isEmpty)
        statusItem.button?.image = image
        statusItem.button?.attributedTitle = StatusItemContent.title(items: presentation.items, leadingSpace: image != nil)
        popover.appearance = model.settings.appearance.nativeAppearance
        let errors = [model.quotaError.map { "额度：" + $0 }, model.statisticsError.map { "统计：" + $0 }].compactMap { $0 }
        let news = indicator ? "有 \(model.unreadNewsCount) 条未读重置动态，点击查看\n" : ""
        let detail = title.isEmpty ? "" : title.replacingOccurrences(of: " · ", with: "\n") + "\n"
        statusItem.button?.toolTip = "Codex Usage\n" + news + detail + (errors.isEmpty ? "点击查看额度和用量统计" : errors.joined(separator: "\n"))
        statusItem.button?.setAccessibilityLabel(news + (title.isEmpty ? "Codex 用量" : "Codex 用量，" + title))
    }
    @objc private func togglePopover() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let settings = NSMenuItem(title: "设置…", action: #selector(settingsAction), keyEquivalent: ",")
            settings.target = self; menu.addItem(settings)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: "退出 Codex Usage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp; menu.addItem(quit)
            statusItem.menu = menu; statusItem.button?.performClick(nil); statusItem.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil) }
        else { showPopover() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return false
        }
        showPopover(); return false
    }
    private func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        model.resumeIfNeeded()
        if model.showNewsIndicator { model.selectedTab = .resetNews }
        // 状态项可能位于外接屏；同一高度同时交给 SwiftUI 和 NSPopover。
        let availableHeight = button.window?.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 692
        model.panelHeight = PanelLayout.height(availableHeight: availableHeight)
        popover.contentSize = NSSize(width: 400, height: model.panelHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
    func popoverDidShow(_ notification: Notification) { model.setPanelVisible(true) }
    func popoverDidClose(_ notification: Notification) { model.setPanelVisible(false) }
    func applicationWillTerminate(_ notification: Notification) {
        model.stop(); networkMonitor.cancel()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
    @objc private func settingsAction() { openSettings() }
    private func openSettings() {
        popover.performClose(nil)
        NSApp.setActivationPolicy(.regular)
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Codex Usage 设置"; window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: model) { [weak window] in window?.close() })
        window.center(); window.makeKeyAndOrderFront(nil)
        settingsWindow = window; NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
    private func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let settings = NSMenuItem(title: "设置…", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self; appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Codex Usage", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp; appMenu.addItem(quit)
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "编辑"); editItem.submenu = edit
        for (title, action, key) in [("剪切", "cut:", "x"), ("复制", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        NSApp.mainMenu = main
    }
}
