import Foundation
import UserNotifications

final class LowBalanceNotifications: NSObject, UNUserNotificationCenterDelegate {
    var onStatus: ((String?) -> Void)?
    var isRelevant: ((String, Double) -> Bool)?
    private let center = UNUserNotificationCenter.current()
    private var askingPermission = false
    private var pending: [String: (name: String, remaining: Double, threshold: Double)] = [:]

    override init() {
        super.init()
        center.delegate = self
    }

    func prepare() {
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async { self?.handle(settings) }
        }
    }

    func notify(profile: PanelProfile, remaining: Double) {
        guard let threshold = profile.lowBalanceThreshold else { return }
        pending[profile.id] = (profile.name, remaining, threshold)
        prepare()
    }

    private func handle(_ settings: UNNotificationSettings) {
        switch settings.authorizationStatus {
        case .notDetermined:
            guard !askingPermission else { return }
            askingPermission = true
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, error in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.askingPermission = false
                    if error != nil {
                        self.onStatus?("Не удалось запросить уведомления. Проверьте разрешения macOS.")
                        self.pending.removeAll()
                    } else { self.prepare() }
                }
            }
        case .authorized, .provisional:
            onStatus?(settings.alertSetting == .disabled ? "Баннеры отключены в настройках уведомлений macOS. Оранжевый счётчик продолжит работать." : nil)
            let work = pending
            pending.removeAll()
            for (id, item) in work {
                guard isRelevant?(id, item.threshold) == true else { continue }
                let content = UNMutableNotificationContent()
                content.title = "\(item.name): заканчиваются токены"
                content.body = "Осталось \(Balance.compact(item.remaining)) — меньше порога \(Balance.compact(item.threshold))."
                content.sound = .default
                let request = UNNotificationRequest(identifier: "low-balance-" + id, content: content, trigger: nil)
                center.add(request) { [weak self] error in
                    if error != nil {
                        DispatchQueue.main.async { self?.onStatus?("Не удалось показать уведомление. Оранжевый счётчик продолжит работать.") }
                    }
                }
            }
        case .denied:
            pending.removeAll()
            onStatus?("Уведомления запрещены. Разрешите их для BetterTokenPanel в настройках macOS. Цветовое предупреждение работает без разрешения.")
        @unknown default:
            pending.removeAll()
            onStatus?("Проверьте разрешение на уведомления в настройках macOS.")
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
