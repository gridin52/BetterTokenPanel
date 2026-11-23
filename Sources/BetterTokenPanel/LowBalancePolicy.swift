import Foundation

struct LowBalanceLatch: Codable, Equatable {
    let threshold: Double
}

enum LowBalancePolicy {
    static func isValidThreshold(_ value: Double) -> Bool {
        value.isFinite && value > 0 && value.rounded(.towardZero) == value && value <= 9_007_199_254_740_991
    }

    static func isLow(_ remaining: Double?, threshold: Double?) -> Bool {
        guard let remaining = remaining, let threshold = threshold,
              remaining.isFinite, remaining >= 0, isValidThreshold(threshold) else { return false }
        return remaining < threshold
    }

    // Called only for successful fresh readings. No sample / a network error
    // neither clears a warning nor starts a new notification episode.
    static func transition(previous: LowBalanceLatch?, remaining: Double, threshold: Double?) -> (latch: LowBalanceLatch?, notify: Bool) {
        guard remaining.isFinite, remaining >= 0 else { return (previous, false) }
        guard let threshold = threshold, isValidThreshold(threshold) else { return (nil, false) }
        guard remaining < threshold else { return (nil, false) }
        return (LowBalanceLatch(threshold: threshold), previous?.threshold != threshold)
    }

    // Plain token count; suffixes are intentionally not guessed in settings.
    static func parseThreshold(_ text: String) throws -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard trimmed.range(of: "^[0-9]+$", options: .regularExpression) != nil,
              let value = Double(trimmed), isValidThreshold(value) else { throw LowBalanceError.invalidThreshold }
        return value
    }
}

enum LowBalanceError: LocalizedError {
    case invalidThreshold
    var errorDescription: String? {
        "Введите положительное целое количество токенов, например 10000000. Пустое поле отключает предупреждение."
    }
}
