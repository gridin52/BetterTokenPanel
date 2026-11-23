import Foundation

struct DetectorRule: Codable, Equatable {
    var version: Int
    var selector: String
    var contextSelector: String
    var labelSelector: String
    var anchor: String

    var isValid: Bool {
        version == 1 && !selector.isEmpty && !contextSelector.isEmpty && !anchor.isEmpty &&
        selector.count <= 8192 && contextSelector.count <= 8192 && labelSelector.count <= 8192 && anchor.count <= 30000
    }
}

struct DetectorCandidate: Decodable, Identifiable {
    let id: String
    let label: String
    let display: String
    let value: Double
    let rule: DetectorRule

    static func decode(_ value: Any) -> DetectorCandidate? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let result = try? JSONDecoder().decode(Self.self, from: data),
              result.value.isFinite, result.value >= 0, result.rule.isValid else { return nil }
        return result
    }
}

// Both the URL and DOM fingerprint can contain secrets; keep the whole record in Keychain.
struct DashboardAccess: Codable {
    let url: URL
    let rule: DetectorRule?
}

enum DetectorScripts {
    static func resource(_ name: String) -> String? {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(forResource: name, withExtension: "js")
        #else
        let url = Bundle.main.url(forResource: name, withExtension: "js")
        #endif
        return url.flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    }
    static func call(_ operation: Operation, rule: DetectorRule? = nil) -> String? {
        guard let source = resource("PanelDetector") else { return nil }
        let invocation: String
        switch operation {
        case .scan: invocation = "scan()"
        case .enablePicker: invocation = "enablePicker(true)"
        case .disablePicker: invocation = "enablePicker(false)"
        case .selection: invocation = "takePickerEvent()"
        case .stop: invocation = "stop(); null"
        case .read, .highlight:
            guard let rule = rule, rule.isValid,
                  let data = try? JSONEncoder().encode(rule),
                  let json = String(data: data, encoding: .utf8) else { return nil }
            invocation = (operation == .read ? "read(" : "highlight(") + json + ")"
        }
        return source + "\n; globalThis.BTPDetector." + invocation
    }
    static func pickPoint(x: Double, y: Double) -> String? {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y),
              let source = resource("PanelDetector"),
              let data = try? JSONSerialization.data(withJSONObject: [x, y]),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return source + "\n; globalThis.BTPDetector.pickAtPoint(..." + json + ")"
    }

    enum Operation: Equatable { case scan, read, highlight, enablePicker, disablePicker, selection, stop }
}
