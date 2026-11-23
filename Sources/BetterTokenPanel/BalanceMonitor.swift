import AppKit
import WebKit

final class BalanceMonitor: NSObject, WKNavigationDelegate {
    var onChange: (() -> Void)?
    var onFreshBalance: ((Double) -> Void)?
    private(set) var balance: Balance?
    private(set) var message = "Добавьте ссылку на панель"
    private(set) var loading = false
    private(set) var hasError = false
    private(set) var dashboardURL: URL?
    private var access: DashboardAccess?
    private var webView: WKWebView?
    private var refreshTimer: Timer?
    private var pollTimer: Timer?
    private var deadline = Date.distantPast
    private var generation = 0
    private var evaluating = false
    private let account: String
    private(set) var interval: TimeInterval

    init(account: String, interval: TimeInterval) {
        self.account = account
        self.interval = interval
        super.init()
        setInterval(interval)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
    }

    func setInterval(_ seconds: TimeInterval) {
        interval = seconds
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = min(seconds * 0.1, 5)
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func replaceAccess(_ access: DashboardAccess) {
        cancel()
        self.access = access
        dashboardURL = access.url
        balance = nil
        hasError = false
        refresh()
    }

    func stop() {
        onChange = nil
        onFreshBalance = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        cancel()
        dashboardURL = nil
        access = nil
        balance = nil
    }

    deinit {
        refreshTimer?.invalidate()
        pollTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func refresh() {
        guard !loading else { return }
        if access == nil {
            do {
                access = try DashboardCredential.loadAccess(account: account)
                dashboardURL = access?.url
            } catch { fail(error.localizedDescription); return }
        }
        guard let access = access else {
            fail("Ссылка не найдена в связке ключей. Добавьте её заново в настройках панели.")
            return
        }
        guard access.rule != nil || DashboardCredential.isKnownDashboard(access.url) else {
            fail("Откройте настройки и выберите, откуда читать баланс этой панели.")
            return
        }
        generation += 1
        loading = true
        if !hasError { message = "Обновляем баланс…" }
        deadline = Date().addingTimeInterval(45)
        evaluating = false
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 900), configuration: config)
        view.navigationDelegate = self
        webView = view
        view.load(URLRequest(url: access.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.readBalance() }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        onChange?()
    }

    @objc private func woke() { refresh() }

    private func readBalance() {
        guard loading else { return }
        if Date() >= deadline {
            fail("Выбранный счётчик не найден или изменился. Откройте настройки и выберите баланс заново. При техработах повторите обновление позже.")
            return
        }
        guard !evaluating, let view = webView, let access = access else { return }
        let script: String?
        if let rule = access.rule { script = DetectorScripts.call(.read, rule: rule) }
        else { script = DetectorScripts.resource("BalanceReader") }
        guard let script = script else { fail("В сборке отсутствует скрипт чтения панели. Пересоберите приложение."); return }
        evaluating = true
        let requestGeneration = generation
        view.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            guard let self = self, self.generation == requestGeneration, self.loading else { return }
            self.evaluating = false
            guard case .success(let raw) = result, let data = raw as? [String: Any],
                  let remaining = data["remaining"] as? NSNumber,
                  remaining.doubleValue.isFinite, remaining.doubleValue >= 0 else { return }
            self.balance = Balance(remaining: remaining.doubleValue,
                                   spent: (data["spent"] as? NSNumber)?.doubleValue,
                                   total: (data["total"] as? NSNumber)?.doubleValue,
                                   fetchedAt: Date())
            self.message = "Баланс обновлён"
            self.hasError = false
            self.cancel()
            self.onFreshBalance?(remaining.doubleValue)
            self.onChange?()
        }
    }

    private func cancel() {
        generation += 1
        pollTimer?.invalidate()
        pollTimer = nil
        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil
        loading = false
        evaluating = false
    }

    private func fail(_ text: String) {
        cancel()
        hasError = true
        message = text
        onChange?()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === self.webView else { return }
        readBalance()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        fail("Не удалось загрузить панель. Проверьте интернет и доступность сервиса.")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === self.webView else { return }
        fail("Панель недоступна. Проверьте интернет, ссылку или сертификат сервиса.")
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let dashboard = dashboardURL, action.targetFrame != nil,
              PanelNavigation.permits(action.request.url, for: dashboard) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let dashboard = dashboardURL, response.canShowMIMEType,
              PanelNavigation.permits(response.response.url, for: dashboard) else { decisionHandler(.cancel); return }
        decisionHandler(.allow)
    }
}
