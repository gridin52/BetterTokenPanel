import Foundation
import SwiftUI

struct PanelProfile: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var interval: TimeInterval
    var tint: PanelTint
    var lowBalanceThreshold: Double? = nil

    static let intervals: [TimeInterval] = [30, 60, 120, 300, 600, 900, 1800, 3600]
    static func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "30 секунд" }
        if seconds == 3600 { return "1 час" }
        return "\(Int(seconds / 60)) мин"
    }

    static func normalizedName(_ input: String) -> String {
        input.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

enum PanelTint: String, Codable, CaseIterable, Identifiable {
    case blue, mint, violet, amber, rose
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return Color(red: 0.27, green: 0.51, blue: 0.97)
        case .mint: return Color(red: 0.15, green: 0.67, blue: 0.53)
        case .violet: return Color(red: 0.61, green: 0.43, blue: 0.91)
        case .amber: return Color(red: 0.85, green: 0.57, blue: 0.13)
        case .rose: return Color(red: 0.87, green: 0.36, blue: 0.49)
        }
    }
    var label: String {
        switch self {
        case .blue: return "Синий"
        case .mint: return "Мятный"
        case .violet: return "Фиолетовый"
        case .amber: return "Янтарный"
        case .rose: return "Розовый"
        }
    }
}

final class PanelModel: ObservableObject {
    @Published private(set) var profiles: [PanelProfile] = []
    @Published var revision = 0
    @Published private(set) var startupError: String?
    private var monitors: [String: BalanceMonitor] = [:]
    private let defaults: UserDefaults
    private static let storageKey = "panel-profiles-v2"
    var onChange: (() -> Void)?
    var settings: (() -> Void)?
    var quit: (() -> Void)?
    var onLowBalance: ((PanelProfile, Double) -> Void)?
    var onAlertConfigured: (() -> Void)?
    @Published var notificationStatus: String?
    private var lowBalanceLatches: [String: LowBalanceLatch] = [:]
    private static let latchKey = "low-balance-latches-v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.latchKey),
           let saved = try? JSONDecoder().decode([String: LowBalanceLatch].self, from: data) {
            lowBalanceLatches = saved
        }
        if let data = defaults.data(forKey: Self.storageKey) {
            do {
                let saved = try JSONDecoder().decode([PanelProfile].self, from: data)
                guard Set(saved.map(\.id)).count == saved.count,
                      saved.allSatisfy({ !$0.id.isEmpty && !PanelProfile.normalizedName($0.name).isEmpty && PanelProfile.intervals.contains($0.interval) }) else {
                    throw ProfileError.invalidSettings
                }
                guard saved.allSatisfy({ $0.lowBalanceThreshold.map(LowBalancePolicy.isValidThreshold) ?? true }) else {
                    throw LowBalanceError.invalidThreshold
                }
                profiles = saved
                installMonitors()
            } catch { startupError = "Не удалось прочитать настройки. Они не перезаписаны. Восстановите настройки приложения из резервной копии." }
        } else { retryMigration() }
    }

    func retryMigration() {
        guard defaults.data(forKey: Self.storageKey) == nil else { return }
        do {
            // Retain the old Keychain account: migration never copies the secret to preferences.
            if try DashboardCredential.load() != nil {
                profiles = [PanelProfile(id: "dashboard-url", name: "Claude", interval: 60, tint: .blue)]
            }
            try persist(profiles)
            startupError = nil
            installMonitors()
            notify()
        } catch { startupError = error.localizedDescription }
    }

    func monitor(for id: String) -> BalanceMonitor? { monitors[id] }
    func start() { monitors.values.forEach { $0.refresh() } }

    func save(id: String?, name: String, interval: TimeInterval, tint: PanelTint, link: String, rule: DetectorRule? = nil, lowBalanceThreshold: Double? = nil) throws {
        guard startupError == nil else { throw ProfileError.invalidSettings }
        let cleaned = PanelProfile.normalizedName(name)
        guard !cleaned.isEmpty, cleaned.count <= 16 else { throw ProfileError.invalidName }
        guard PanelProfile.intervals.contains(interval) else { throw ProfileError.invalidInterval }
        guard !profiles.contains(where: { $0.id != id && $0.name.localizedCaseInsensitiveCompare(cleaned) == .orderedSame }) else {
            throw ProfileError.duplicateName
        }
        let existing = id.flatMap { key in profiles.first { $0.id == key } }
        if id != nil && existing == nil { throw ProfileError.invalidSettings }
        if let threshold = lowBalanceThreshold, !LowBalancePolicy.isValidThreshold(threshold) { throw LowBalanceError.invalidThreshold }
        let profile = PanelProfile(id: existing?.id ?? UUID().uuidString, name: cleaned, interval: interval, tint: tint, lowBalanceThreshold: lowBalanceThreshold)
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: URL?
        if trimmed.isEmpty { url = nil }
        else { url = try DashboardCredential.validate(trimmed) }
        if existing == nil && url == nil { throw ProfileError.missingURL }
        if url != nil && (rule == nil || rule?.isValid != true) { throw CredentialError.invalidRule }
        if url == nil && rule != nil { throw CredentialError.invalidRule }
        // Encode before updating Keychain, so a coding failure cannot orphan a new credential.
        var next = profiles
        if let index = next.firstIndex(where: { $0.id == profile.id }) { next[index] = profile }
        else { next.append(profile) }
        let encoded = try JSONEncoder().encode(next)
        let access = url.map { DashboardAccess(url: $0, rule: rule) }
        if let access = access { try DashboardCredential.saveAccess(access, account: profile.id) }
        defaults.set(encoded, forKey: Self.storageKey)
        profiles = next
        let thresholdChanged = existing?.lowBalanceThreshold != profile.lowBalanceThreshold
        if thresholdChanged || access != nil {
            lowBalanceLatches.removeValue(forKey: profile.id)
            persistLatches()
        }
        if profile.lowBalanceThreshold != nil { onAlertConfigured?() }
        if let monitor = monitors[profile.id] {
            monitor.setInterval(interval)
            if let access = access { monitor.replaceAccess(access) }
            else if thresholdChanged && profile.lowBalanceThreshold != nil { monitor.refresh() }
        } else {
            let monitor = makeMonitor(profile)
            monitors[profile.id] = monitor
            monitor.refresh()
        }
        notify()
    }

    func remove(_ id: String) throws {
        let next = profiles.filter { $0.id != id }
        let encoded = try JSONEncoder().encode(next)
        try DashboardCredential.delete(account: id)
        monitors[id]?.stop()
        monitors.removeValue(forKey: id)
        lowBalanceLatches.removeValue(forKey: id)
        persistLatches()
        defaults.set(encoded, forKey: Self.storageKey)
        profiles = next
        notify()
    }

    private func persist(_ items: [PanelProfile]) throws {
        defaults.set(try JSONEncoder().encode(items), forKey: Self.storageKey)
    }
    private func installMonitors() {
        monitors.values.forEach { $0.stop() }
        monitors = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, makeMonitor($0)) })
    }
    private func makeMonitor(_ profile: PanelProfile) -> BalanceMonitor {
        let monitor = BalanceMonitor(account: profile.id, interval: profile.interval)
        monitor.onChange = { [weak self] in self?.notify() }
        monitor.onFreshBalance = { [weak self] remaining in self?.processFreshBalance(id: profile.id, remaining: remaining) }
        return monitor
    }

    func isLow(_ profile: PanelProfile) -> Bool {
        LowBalancePolicy.isLow(monitors[profile.id]?.balance?.remaining, threshold: profile.lowBalanceThreshold)
    }

    private func processFreshBalance(id: String, remaining: Double) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        let result = LowBalancePolicy.transition(previous: lowBalanceLatches[id], remaining: remaining, threshold: profile.lowBalanceThreshold)
        if result.latch != lowBalanceLatches[id] {
            lowBalanceLatches[id] = result.latch
            persistLatches()
        }
        if result.notify { onLowBalance?(profile, remaining) }
    }

    private func persistLatches() {
        if let data = try? JSONEncoder().encode(lowBalanceLatches) { defaults.set(data, forKey: Self.latchKey) }
    }
    private func notify() { revision += 1; onChange?() }
}

enum ProfileError: LocalizedError {
    case invalidName, duplicateName, invalidInterval, missingURL, invalidSettings
    var errorDescription: String? {
        switch self {
        case .invalidName: return "Введите название от 1 до 16 символов. Оно появится в строке меню."
        case .duplicateName: return "Такая панель уже есть. Задайте другое название, чтобы различать счётчики."
        case .invalidInterval: return "Выберите интервал обновления из списка."
        case .missingURL: return "Для новой панели нужна персональная ссылка."
        case .invalidSettings: return "Настройки недоступны. Закройте окно и проверьте состояние приложения."
        }
    }
}
