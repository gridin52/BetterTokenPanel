import AppKit
import Foundation

// Never register/unregister real login items during tests.
@main
struct LaunchAtLoginTests {
    static func main() {
        _ = NSApplication.shared
        let suite = "com.bettertokenpanel.login-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let launch = LaunchAtLogin(defaults: defaults)
        precondition(launch.isFirstRunQuestionNeeded)
        launch.refresh()
        precondition(launch.isFirstRunQuestionNeeded, "Reading status must not answer onboarding")
        launch.markQuestionAnswered()
        precondition(!launch.isFirstRunQuestionNeeded)
        let restored = LaunchAtLogin(defaults: defaults)
        precondition(!restored.isFirstRunQuestionNeeded, "Declining must survive a restart")
        restored.markQuestionAnswered()
        precondition(!restored.isFirstRunQuestionNeeded)
        print("Launch-at-login onboarding persistence checks passed. System registration was not modified.")
    }
}
