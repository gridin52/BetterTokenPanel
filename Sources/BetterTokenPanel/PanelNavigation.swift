import Foundation
import WebKit

// A supplied dashboard may use any public HTTPS domain, but may not navigate to another origin.
enum PanelNavigation {
    static func permits(_ url: URL?, for dashboard: URL) -> Bool {
        guard let url = url, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil else { return false }
        return url.host?.lowercased() == dashboard.host?.lowercased() && (url.port ?? 443) == (dashboard.port ?? 443)
    }
}
