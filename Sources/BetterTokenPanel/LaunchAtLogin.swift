import AppKit
import ServiceManagement
import SwiftUI

final class LaunchAtLogin: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published private(set) var status: String?
    private let defaults: UserDefaults
    private var activationObserver: NSObjectProtocol?
    private static let askedKey = "launch-at-login-asked-v1"
    private var lastError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let observer = activationObserver { NotificationCenter.default.removeObserver(observer) }
    }

    var isFirstRunQuestionNeeded: Bool { !defaults.bool(forKey: Self.askedKey) }
    func markQuestionAnswered() { defaults.set(true, forKey: Self.askedKey) }

    func refresh() {
        let actual = SMAppService.mainApp.status
        enabled = actual == .enabled || actual == .requiresApproval
        needsApproval = actual == .requiresApproval
        switch actual {
        case .enabled:
            lastError = nil
            status = nil
        case .requiresApproval:
            status = "Нужно одобрение macOS. Разрешите BetterTokenPanel в разделе «Объекты входа»."
        case .notFound:
            status = "macOS не нашла приложение для автозапуска. Перенесите .app в «Программы», запустите его оттуда и повторите попытку."
        case .notRegistered:
            status = lastError
        @unknown default:
            status = "Проверьте состояние автозапуска в системных настройках."
        }
    }

    func set(_ value: Bool) {
        // A deliberate setting change also counts as answering the onboarding question.
        markQuestionAnswered()
        lastError = nil
        do {
            if value {
                if SMAppService.mainApp.status != .enabled && SMAppService.mainApp.status != .requiresApproval {
                    try SMAppService.mainApp.register()
                }
            } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastError = "Не удалось изменить автозапуск. Перенесите приложение в «Программы» и проверьте объекты входа macOS."
        }
        refresh()
        if let error = lastError { status = error }
    }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

struct LaunchAtLoginSettings: View {
    @ObservedObject var launch: LaunchAtLogin

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Toggle(isOn: Binding(get: { launch.enabled }, set: { launch.set($0) })) {
                Label("Запускать при входе в macOS", systemImage: "power.circle")
                    .font(.system(size: 12, weight: .semibold))
            }.toggleStyle(.switch)
            Text("Общая настройка приложения. Меняется сразу, без кнопки «Сохранить». После входа в macOS счётчики появятся в строке меню.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let status = launch.status {
                Label(status, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                Button("Открыть объекты входа macOS") { launch.openSystemSettings() }
                    .font(.caption)
            }
        }.onAppear { launch.refresh() }
    }
}
