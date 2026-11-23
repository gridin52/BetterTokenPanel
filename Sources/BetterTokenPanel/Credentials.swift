import Foundation
import Security

// The entire dashboard URL is a credential. Never log or persist it in preferences.
enum DashboardCredential {
    private static let service = "com.bettertokenpanel.dashboard"
    private static let account = "dashboard-url"

    static func validate(_ input: String) throws -> URL {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), host.contains("."),
              !host.hasSuffix(".local"), !host.hasSuffix(".localhost"),
              !host.contains(":"), host.range(of: "^[0-9.]+$", options: .regularExpression) == nil,
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443 else { throw CredentialError.invalidURL }
        return url
    }

    static func isKnownDashboard(_ url: URL) -> Bool {
        let parts = url.pathComponents.filter { $0 != "/" }
        return url.host?.lowercased() == "claude-n-codex.com" && parts.count == 3 &&
            parts[0] == "dashboard" && parts[1].hasPrefix("sk-") && parts[2] == "v5"
    }

    static func load(account: String = "dashboard-url") throws -> URL? {
        try loadAccess(account: account)?.url
    }

    static func loadAccess(account: String) throws -> DashboardAccess? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw CredentialError.keychain(status)
        }
        if let access = try? JSONDecoder().decode(DashboardAccess.self, from: data) {
            _ = try validate(access.url.absoluteString)
            if let rule = access.rule, !rule.isValid { throw CredentialError.invalidRule }
            return access
        }
        guard let string = String(data: data, encoding: .utf8) else { throw CredentialError.invalidURL }
        return DashboardAccess(url: try validate(string), rule: nil)
    }

    static func save(_ url: URL, account: String = "dashboard-url") throws {
        try saveAccess(DashboardAccess(url: url, rule: nil), account: account)
    }

    static func saveAccess(_ access: DashboardAccess, account: String) throws {
        _ = try validate(access.url.absoluteString)
        if let rule = access.rule, !rule.isValid { throw CredentialError.invalidRule }
        let data = try JSONEncoder().encode(access)
        let query = baseQuery(account: account)
        let updates = [kSecValueData as String: data] as CFDictionary
        let status = SecItemUpdate(query as CFDictionary, updates)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialError.keychain(added) }
        } else if status != errSecSuccess { throw CredentialError.keychain(status) }
    }

    static func delete(account: String = "dashboard-url") throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialError.keychain(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
}

enum CredentialError: LocalizedError {
    case invalidURL
    case invalidRule
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Введите HTTPS-ссылку на публичную панель: без логина в адресе, нестандартного порта и фрагмента #. Локальные адреса и IP-адреса не поддерживаются."
        case .invalidRule:
            return "Правило чтения повреждено. Выберите счётчик заново."
        case .keychain:
            return "Не удалось открыть связку ключей macOS. Разрешите доступ и повторите попытку."
        }
    }
}

struct Balance {
    let remaining: Double
    let spent: Double?
    let total: Double?
    let fetchedAt: Date

    static func compact(_ value: Double) -> String {
        let scale: Double = value >= 1e9 ? 1e9 : value >= 1e6 ? 1e6 : value >= 1e3 ? 1e3 : 1
        let suffix = scale == 1e9 ? "B" : scale == 1e6 ? "M" : scale == 1e3 ? "K" : ""
        return String(format: scale == 1 ? "%.0f%@" : "%.1f%@", value / scale, suffix)
    }
}
