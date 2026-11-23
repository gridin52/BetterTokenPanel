import AppKit
import SwiftUI

@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = PanelModel()
    private let launchAtLogin = LaunchAtLogin()
    private var statusItems: [String: NSStatusItem] = [:]
    private let panel = NSPopover()
    private var shownID: String?
    private var settingsWindow: NSWindow?
    private let emptyID = "__empty__"
    private var notifications: LowBalanceNotifications?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let editItem = NSMenuItem(title: "Правка", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Правка")
        edit.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
        NSApp.setActivationPolicy(.accessory)
        panel.behavior = .transient
        panel.animates = true
        model.settings = { [weak self] in self?.showSettings() }
        model.quit = { NSApp.terminate(nil) }
        model.onChange = { [weak self] in self?.syncStatusItems() }
        let notifications = LowBalanceNotifications()
        notifications.onStatus = { [weak self] message in self?.model.notificationStatus = message }
        notifications.isRelevant = { [weak self] id, threshold in
            guard let self = self, let profile = self.model.profiles.first(where: { $0.id == id }),
                  profile.lowBalanceThreshold == threshold, let monitor = self.model.monitor(for: id), !monitor.hasError else { return false }
            return self.model.isLow(profile)
        }
        self.notifications = notifications
        model.onLowBalance = { [weak notifications] profile, remaining in notifications?.notify(profile: profile, remaining: remaining) }
        model.onAlertConfigured = { [weak notifications] in notifications?.prepare() }
        if model.profiles.contains(where: { $0.lowBalanceThreshold != nil }) { notifications.prepare() }
        syncStatusItems()
        model.start()
        DispatchQueue.main.async { [weak self] in self?.askAboutLaunchAtLogin() }
    }

    private func askAboutLaunchAtLogin() {
        guard launchAtLogin.isFirstRunQuestionNeeded else { return }
        launchAtLogin.refresh()
        // Preserve an existing system registration without asking to enable it again.
        if launchAtLogin.enabled {
            launchAtLogin.markQuestionAnswered()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Запускать BetterTokenPanel при входе в macOS?"
        alert.informativeText = "Счётчики токенов будут появляться в строке меню автоматически. Вы сможете изменить это в настройках приложения."
        alert.addButton(withTitle: "Включить автозапуск")
        alert.addButton(withTitle: "Не сейчас")
        alert.buttons[1].keyEquivalent = "\u{1b}"
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        launchAtLogin.markQuestionAnswered()
        if response == .alertFirstButtonReturn {
            launchAtLogin.set(true)
            if launchAtLogin.status != nil { showSettings() }
        }
    }

    private func syncStatusItems() {
        let desired = model.profiles.isEmpty ? [emptyID] : model.profiles.map(\.id)
        for id in Array(statusItems.keys) where !desired.contains(id) {
            if shownID == id { panel.performClose(nil); shownID = nil }
            if let item = statusItems.removeValue(forKey: id) { NSStatusBar.system.removeStatusItem(item) }
        }
        for id in desired {
            let item: NSStatusItem
            if let existing = statusItems[id] { item = existing }
            else {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.target = self
                item.button?.action = #selector(togglePanel(_:))
                item.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
                statusItems[id] = item
            }
            guard let profile = model.profiles.first(where: { $0.id == id }), let monitor = model.monitor(for: id) else {
                item.button?.title = " Токены"
                item.button?.image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "Добавить панель")
                item.button?.toolTip = "BetterTokenPanel — добавить панель"
                continue
            }
            let value = monitor.balance.map { Balance.compact($0.remaining) } ?? "—"
            let low = model.isLow(profile)
            let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            let title = NSMutableAttributedString(string: " \(profile.name) ", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            title.append(NSAttributedString(string: value, attributes: [.font: font, .foregroundColor: low ? NSColor.systemOrange : NSColor.labelColor]))
            if monitor.hasError { title.append(NSAttributedString(string: " !", attributes: [.font: font, .foregroundColor: NSColor.systemOrange])) }
            item.button?.attributedTitle = title
            item.button?.image = statusDot(profile.tint, error: monitor.hasError || low)
            item.button?.imagePosition = .imageLeading
            item.button?.toolTip = "\(profile.name) · обновление: \(PanelProfile.intervalLabel(profile.interval))\(low ? " · токенов меньше порога" : "")\(monitor.hasError ? " · не удалось обновить" : "")"
            item.button?.setAccessibilityLabel("\(profile.name): \(value) токенов\(low ? ", ниже порога" : "")\(monitor.hasError ? ", значение устарело" : "")")
        }
    }

    private func statusDot(_ tint: PanelTint, error: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 9, height: 16), flipped: false) { _ in
            (error ? NSColor.systemOrange : NSColor(tint.color)).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1, y: 5, width: 6, height: 6)).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        guard let id = statusItems.first(where: { $0.value.button === sender })?.key else { return }
        if panel.isShown && shownID == id { panel.performClose(nil); shownID = nil; return }
        panel.performClose(nil)
        shownID = id
        panel.contentViewController = NSHostingController(rootView: PanelView(model: model, profileID: id))
        panel.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        panel.contentViewController?.view.window?.makeKey()
    }

    private func showSettings() {
        panel.performClose(nil)
        if settingsWindow == nil {
            let view = SettingsView(model: model, launchAtLogin: launchAtLogin) { [weak self] in self?.settingsWindow?.close() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "BetterTokenPanel"
            window.titlebarAppearsTransparent = true
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        settingsWindow?.contentViewController = nil
        settingsWindow = nil
    }
}
