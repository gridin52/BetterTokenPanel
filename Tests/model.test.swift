import AppKit
import Foundation

// These tests intentionally never save, read, or delete real Keychain credentials.
@main
struct ModelTests {
    static func main() throws {
        _ = NSApplication.shared
        let suite = "com.bettertokenpanel.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let key = "panel-profiles-v2"
        let a = PanelProfile(id: "fixture-claude", name: "Claude", interval: 60, tint: .blue)
        let b = PanelProfile(id: "fixture-codex", name: "Codex", interval: 300, tint: .mint)
        defaults.set(try JSONEncoder().encode([a, b]), forKey: key)
        let model = PanelModel(defaults: defaults)
        precondition(model.profiles == [a, b])
        precondition(model.monitor(for: a.id) !== model.monitor(for: b.id))
        precondition(model.monitor(for: b.id)?.interval == 300)
        try model.save(id: a.id, name: "  Claude   Work  ", interval: 30, tint: .violet, link: "")
        precondition(model.profiles[0].name == "Claude Work")
        precondition(model.monitor(for: a.id)?.interval == 30)
        precondition(model.monitor(for: b.id)?.interval == 300)
        precondition(model.profiles[0].tint == .violet)
        let restored = PanelModel(defaults: defaults)
        precondition(restored.profiles == model.profiles)
        func rejects(_ action: () throws -> Void) {
            do { try action(); fatalError("Expected validation failure") }
            catch { }
        }
        rejects { try model.save(id: a.id, name: "codex", interval: 60, tint: .blue, link: "") }
        rejects { try model.save(id: a.id, name: " ", interval: 60, tint: .blue, link: "") }
        rejects { try model.save(id: a.id, name: String(repeating: "x", count: 17), interval: 60, tint: .blue, link: "") }
        rejects { try model.save(id: a.id, name: "Claude", interval: 1, tint: .blue, link: "") }
        rejects { try model.save(id: nil, name: "New", interval: 60, tint: .blue, link: "") }
        rejects { try model.save(id: "absent", name: "Other", interval: 60, tint: .blue, link: "") }
        _ = try DashboardCredential.validate("https://example.org/dashboard?key=placeholder")
        rejects { _ = try DashboardCredential.validate("http://claude-n-codex.com/dashboard/sk-placeholder/v5") }
        rejects { _ = try DashboardCredential.validate("https://127.0.0.1/panel") }
        rejects { _ = try DashboardCredential.validate("https://example.local/panel") }
        rejects { _ = try DashboardCredential.validate("https://example.org:8443/panel") }
        rejects { _ = try DashboardCredential.validate("https://user:password@example.org/panel") }
        rejects { _ = try DashboardCredential.validate("https://example.org/panel#secret") }
        _ = try DashboardCredential.validate("https://claude-n-codex.com/dashboard/sk-placeholder/v5")
        let origin = URL(string: "https://example.org/panel?key=placeholder")!
        precondition(PanelNavigation.permits(URL(string: "https://example.org:443/other"), for: origin))
        precondition(!PanelNavigation.permits(URL(string: "https://other.example.org/"), for: origin))
        precondition(!PanelNavigation.permits(URL(string: "http://example.org/"), for: origin))
        precondition(!PanelNavigation.permits(URL(string: "https://example.org:8443/"), for: origin))
        let rule = DetectorRule(version: 1, selector: "b", contextSelector: "section", labelSelector: "h3", anchor: "fingerprint")
        precondition(rule.isValid)
        let access = DashboardAccess(url: origin, rule: rule)
        let decodedAccess = try JSONDecoder().decode(DashboardAccess.self, from: JSONEncoder().encode(access))
        precondition(decodedAccess.rule == rule && decodedAccess.url == origin)
        rejects { try model.save(id: a.id, name: "Claude", interval: 60, tint: .blue, link: origin.absoluteString) }
        let legacy = Data("{\"id\":\"legacy\",\"name\":\"Claude\",\"interval\":60,\"tint\":\"blue\"}".utf8)
        let legacyProfile = try JSONDecoder().decode(PanelProfile.self, from: legacy)
        precondition(legacyProfile.lowBalanceThreshold == nil)
        let alertProfile = PanelProfile(id: "threshold", name: "Codex", interval: 60, tint: .mint, lowBalanceThreshold: 10000000)
        let decodedProfile = try JSONDecoder().decode(PanelProfile.self, from: JSONEncoder().encode(alertProfile))
        precondition(decodedProfile.lowBalanceThreshold == 10000000)
        precondition(PanelProfile.intervalLabel(30) == "30 секунд")
        precondition(PanelProfile.intervalLabel(3600) == "1 час")
        precondition(Balance.compact(188100000) == "188.1M")
        let persisted = defaults.data(forKey: key)!
        let text = String(data: persisted, encoding: .utf8)!
        precondition(!text.contains("https://") && !text.contains("sk-"))
        defaults.set(Data("invalid JSON".utf8), forKey: key)
        let broken = PanelModel(defaults: defaults)
        precondition(broken.startupError != nil)
        precondition(defaults.data(forKey: key) == Data("invalid JSON".utf8))
        print("Model checks passed: profiles, independent intervals, persistence, validation, URL allowlist. Keychain/live WebKit not tested.")
    }
}
