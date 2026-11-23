import AppKit
import SwiftUI
import WebKit

final class DiscoverySession: NSObject, ObservableObject, WKNavigationDelegate {
    let url: URL
    let webView: WKWebView
    @Published private(set) var candidates: [DetectorCandidate] = []
    @Published private(set) var selected: DetectorCandidate?
    @Published private(set) var status = "Загружаем панель…"
    @Published private(set) var loading = true
    @Published private(set) var manual = false
    @Published private(set) var checking = false
    private var timer: Timer?
    private var generation = 0
    private var active = false
    private var evaluating = false
    private var ready = false
    private var deadline = Date.distantPast
    private var mouseMonitor: Any?
    private var swallowingMouseSequence = false

    init(url: URL) {
        self.url = url
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        if let source = DetectorScripts.resource("PanelDetector") {
            configuration.userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .defaultClient))
        }
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1050, height: 720), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
    }

    func start() {
        guard !active else { return }
        active = true
        generation += 1
        deadline = Date().addingTimeInterval(45)
        webView.navigationDelegate = self
        installMouseMonitor()
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
        let timer = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        active = false
        if let mouseMonitor = mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        swallowingMouseSequence = false
        generation += 1
        timer?.invalidate()
        timer = nil
        if let script = DetectorScripts.call(.stop) { webView.evaluateJavaScript(script, in: nil, in: .defaultClient, completionHandler: nil) }
        webView.navigationDelegate = nil
        webView.stopLoading()
        candidates = []
        selected = nil
        manual = false
    }

    deinit {
        timer?.invalidate()
        if let mouseMonitor = mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
    }

    private func installMouseMonitor() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
            guard let self = self, self.active else { return event }
            if self.swallowingMouseSequence {
                if event.type == .leftMouseUp { self.swallowingMouseSequence = false }
                return nil
            }
            guard self.manual, self.ready, event.type == .leftMouseDown,
                  event.window === self.webView.window, self.webView.window != nil else { return event }
            let point = self.webView.convert(event.locationInWindow, from: nil)
            let bounds = self.webView.bounds
            guard bounds.contains(point), bounds.width > 0, bounds.height > 0 else { return event }
            self.swallowingMouseSequence = true
            let x = Double((point.x - bounds.minX) / bounds.width)
            let y = Double(self.webView.isFlipped ? (point.y - bounds.minY) / bounds.height : (bounds.maxY - point.y) / bounds.height)
            guard let script = DetectorScripts.pickPoint(x: x, y: y) else {
                self.status = "Не удалось передать клик странице. Выключите и снова включите ручной выбор."
                return nil
            }
            self.evaluate(script) { [weak self] result in self?.handlePickerEvent(result) }
            return nil
        }
    }

    private func handlePickerEvent(_ result: Any?) {
        guard manual else { return }
        guard let event = result as? [String: Any] else { return }
        if let raw = event["candidate"], let candidate = DetectorCandidate.decode(raw) {
            select(candidate)
            return
        }
        switch event["reason"] as? String {
        case "context": status = "Число найдено, но его не удалось надёжно связать с подписью. Нажмите на само значение рядом с названием показателя."
        case "unsupported": status = "Счётчик внутри iframe или canvas пока не поддерживается."
        case "inactive": status = "Режим выбора на странице сбросился. Выключите и снова включите ручной выбор."
        default: status = "Клик получен. Здесь не найдено отдельное число токенов. Нажмите прямо на число, а не на подпись или процент."
        }
    }

    func scanAgain() {
        if !ready {
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
            return
        }
        selected = nil
        candidates = []
        deadline = Date().addingTimeInterval(45)
        setManual(false)
        status = "Ищем подписи и счётчики…"
        tick()
    }

    func setManual(_ enabled: Bool) {
        generation += 1
        evaluating = false
        checking = false
        manual = enabled
        selected = nil
        status = enabled ? "Нажмите прямо на число остатка. Ссылки и кнопки в режиме выбора не выполняются." : "Выберите найденный счётчик или укажите его на странице."
        execute(enabled ? .enablePicker : .disablePicker) { [weak self] result in
            guard let self = self, enabled else { return }
            if (result as? Bool) != true {
                self.manual = false
                self.status = "Не удалось включить выбор на странице. Дождитесь загрузки и попробуйте снова."
            }
        }
    }

    func select(_ candidate: DetectorCandidate) {
        generation += 1
        evaluating = false
        checking = false
        selected = candidate
        manual = false
        execute(.disablePicker) { [weak self] _ in
            self?.execute(.highlight, rule: candidate.rule) { _ in }
        }
        status = "Сверьте выбранное число с остатком токенов, затем подтвердите."
    }

    func confirm(_ completion: @escaping (DetectorRule, Double) -> Void) {
        guard let candidate = selected, !checking else { return }
        checking = true
        execute(.read, rule: candidate.rule) { [weak self] result in
            guard let self = self else { return }
            self.checking = false
            guard let data = result as? [String: Any], let number = data["remaining"] as? NSNumber,
                  number.doubleValue.isFinite, number.doubleValue >= 0 else {
                self.selected = nil
                self.status = "Счётчик изменился. Выберите его заново; другое число автоматически не подставлено."
                return
            }
            completion(candidate.rule, number.doubleValue)
        }
    }

    private func tick() {
        guard active, ready, !evaluating, !checking else { return }
        if manual {
            evaluating = true
            execute(.selection) { [weak self] result in
                guard let self = self else { return }
                self.evaluating = false
                self.handlePickerEvent(result)
            }
        } else if selected == nil && Date() <= deadline {
            evaluating = true
            execute(.scan) { [weak self] result in
                guard let self = self else { return }
                self.evaluating = false
                self.candidates = (result as? [Any] ?? []).compactMap(DetectorCandidate.decode)
                self.status = self.candidates.isEmpty ? "Ищем остаток… Если панель уже загрузилась, можно указать число вручную." : "Найдены возможные счётчики. Выберите нужный и проверьте его на странице."
            }
        } else if selected == nil && candidates.isEmpty {
            status = "Не нашли однозначный остаток. Укажите число на странице или проверьте, доступна ли панель по этой ссылке."
        }
    }

    private func execute(_ operation: DetectorScripts.Operation, rule: DetectorRule? = nil, completion: @escaping (Any?) -> Void) {
        guard active, let script = DetectorScripts.call(operation, rule: rule) else {
            completion(nil)
            return
        }
        evaluate(script, completion: completion)
    }

    private func evaluate(_ script: String, completion: @escaping (Any?) -> Void) {
        let token = generation
        webView.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
            guard let self = self, self.active, self.generation == token else { return }
            if case .success(let value) = result { completion(value) }
            else {
                if self.manual { self.status = "Ошибка чтения страницы. Выключите ручной выбор и попробуйте снова." }
                completion(nil)
            }
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        generation += 1
        ready = false
        evaluating = false
        checking = false
        selected = nil
        candidates = []
        manual = false
        loading = true
        status = "Загружаем панель…"
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        guard active else { return }
        ready = true
        loading = false
        deadline = Date().addingTimeInterval(45)
        tick()
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard active else { return }
        ready = true
        loading = false
        deadline = Date().addingTimeInterval(45)
        tick()
    }
    private func failed() {
        ready = false
        loading = false
        evaluating = false
        checking = false
        selected = nil
        candidates = []
        status = "Не удалось загрузить страницу. Проверьте ссылку, интернет и доступность панели. Переходы на другой домен запрещены."
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed() }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard active, action.targetFrame != nil, PanelNavigation.permits(action.request.url, for: url) else {
            decisionHandler(.cancel)
            if action.targetFrame?.isMainFrame == true {
                generation += 1
                loading = false; ready = false; evaluating = false; checking = false
                selected = nil; candidates = []
                status = "Переход на другой домен заблокирован. Вставьте конечную HTTPS-ссылку панели."
            }
            return
        }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(response.canShowMIMEType && PanelNavigation.permits(response.response.url, for: url) ? .allow : .cancel)
    }
}

private struct DashboardWebView: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) { }
}

struct DiscoveryView: View {
    @StateObject private var session: DiscoverySession
    let onConfirm: (DetectorRule, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    init(url: URL, onConfirm: @escaping (DetectorRule, Double) -> Void) {
        _session = StateObject(wrappedValue: DiscoverySession(url: url))
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "scope").font(.title2).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Откуда читать баланс?").font(.title3).fontWeight(.semibold)
                    Text(session.url.host ?? "Панель").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if session.loading { ProgressView().controlSize(.small) }
                Button("Закрыть") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            HStack(spacing: 0) {
                DashboardWebView(webView: session.webView).frame(minWidth: 620)
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    Text("Выберите остаток").font(.headline)
                    Text(session.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ScrollView {
                        VStack(spacing: 9) {
                            ForEach(session.candidates) { candidate in
                                Button { session.select(candidate) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(Balance.compact(candidate.value)).font(.system(size: 23, weight: .semibold, design: .rounded)).monospacedDigit()
                                            Text("Возможный остаток токенов").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: session.selected?.id == candidate.id ? "checkmark.circle.fill" : "circle").foregroundStyle(.blue)
                                    }.padding(13).background(Color.blue.opacity(session.selected?.id == candidate.id ? 0.12 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Button { session.setManual(!session.manual) } label: {
                        Label(session.manual ? "Отменить выбор кликом" : "Указать на странице", systemImage: "cursorarrow.rays")
                    }.disabled(session.loading)
                    Button("Искать заново") { session.scanAgain() }.disabled(session.loading)
                    Divider()
                    if let selected = session.selected {
                        Text("Выбрано: \(Balance.compact(selected.value))").font(.headline)
                        Text("Это именно остаток токенов, а не потраченные токены, кредиты или деньги?")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        session.confirm { rule, value in onConfirm(rule, value); dismiss() }
                    } label: {
                        Text(session.checking ? "Проверяем…" : "Да, это остаток токенов").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(session.selected == nil || session.checking)
                    Text("Локальный поиск. Страница не отправляется нейросети. Входы и cookies не сохраняются: нужна страница, доступная по самой ссылке.")
                        .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(width: 300)
            }
        }.frame(width: 1000, height: 690)
            .onAppear { session.start() }
            .onDisappear { session.stop() }
    }
}
