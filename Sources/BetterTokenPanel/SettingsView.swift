import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var launchAtLogin: LaunchAtLogin
    var close: () -> Void
    @State private var selectedID: String?
    @State private var name = ""
    @State private var link = ""
    @State private var interval: TimeInterval = 60
    @State private var tint: PanelTint = .blue
    @State private var error: String?
    @State private var notice: String?
    @State private var confirmingRemoval = false
    @State private var discovery: DiscoveryRequest?
    @State private var confirmedAccess: DashboardAccess?
    @State private var detectedValue: Double?
    @State private var thresholdText = ""

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 23) {
                    HStack(spacing: 12) {
                        PanelBadge(name: name.isEmpty ? "+" : name, tint: tint, size: 46)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedID == nil ? "Новая панель" : "Настройки панели")
                                .font(.system(size: 23, weight: .semibold))
                            Text("Свой счётчик. Свой ритм.").foregroundStyle(.secondary)
                        }
                    }
                    if let startupError = model.startupError {
                        Text(startupError).font(.callout).foregroundStyle(.orange)
                        Button("Повторить подключение") { model.retryMigration(); model.start() }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        fieldTitle("Название в строке меню", symbol: "character.cursor.ibeam")
                        TextField("Claude, Codex, рабочий ключ…", text: $name)
                            .textFieldStyle(.roundedBorder)
                        Text("До 16 символов. Название обозначает, чей баланс вы видите.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        fieldTitle("Цвет панели", symbol: "paintpalette")
                        HStack(spacing: 12) {
                            ForEach(PanelTint.allCases) { candidate in
                                Button { tint = candidate } label: {
                                    ZStack {
                                        Circle().fill(candidate.color).frame(width: 27, height: 27)
                                        if tint == candidate { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white) }
                                    }.padding(4).overlay(Circle().stroke(tint == candidate ? candidate.color.opacity(0.5) : .clear, lineWidth: 2))
                                }.buttonStyle(.plain).help(candidate.label)
                                    .accessibilityLabel(candidate.label)
                                    .accessibilityAddTraits(tint == candidate ? .isSelected : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        fieldTitle("Персональная ссылка", symbol: "lock.shield")
                        SecureField(selectedID == nil ? "Вставьте ссылку на панель" : "Оставьте пустым, чтобы не менять", text: $link)
                            .textFieldStyle(.roundedBorder)
                        Text("Можно подключить другую HTTPS-панель. Ссылка и правило чтения сохраняются в связке ключей macOS. Страница должна открываться без отдельного входа.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button { discover() } label: { Label("Найти остаток на странице…", systemImage: "scope") }
                        if let value = detectedValue {
                            Label("Подтверждён остаток: \(Balance.compact(value))", systemImage: "checkmark.seal.fill")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        fieldTitle("Предупреждать, если осталось меньше", symbol: "bell.badge")
                        HStack(spacing: 8) {
                            TextField("Например, 10000000", text: $thresholdText)
                                .textFieldStyle(.roundedBorder).frame(width: 170)
                            Text("токенов").foregroundStyle(.secondary)
                            Spacer()
                            if !thresholdText.isEmpty { Image(systemName: "bell.fill").foregroundStyle(.orange) }
                        }
                        Text("Пустое поле отключает предупреждение. При срабатывании счётчик станет оранжевым, а macOS покажет уведомление один раз до следующего пополнения.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            fieldTitle("Обновлять каждые", symbol: "clock")
                            Text("Отдельный интервал для этой панели.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Интервал", selection: $interval) {
                            ForEach(PanelProfile.intervals, id: \.self) { seconds in
                                Text(PanelProfile.intervalLabel(seconds)).tag(seconds)
                            }
                        }.labelsHidden().frame(width: 120)
                    }
                    HStack(spacing: 8) {
                        Circle().fill(tint.color).frame(width: 6, height: 6)
                        Text("\(name.isEmpty ? "Панель" : name) 188.1M")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Spacer()
                        Text("Пример").font(.caption2).foregroundStyle(.secondary)
                    }.padding(13).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 11))
                        .accessibilityLabel("Пример отображения, не настоящий баланс")
                    if let error = error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.red) }
                    if let notice = notice { Label(notice, systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.green) }
                    if let status = model.notificationStatus {
                        Label(status, systemImage: "bell.slash").font(.caption).foregroundStyle(.orange)
                    }
                    Divider()
                    LaunchAtLoginSettings(launch: launchAtLogin)
                    Divider()
                    HStack {
                        if selectedID != nil {
                            Button("Удалить…", role: .destructive) { confirmingRemoval = true }
                        }
                        Spacer()
                        Button("Закрыть") { link = ""; close() }.keyboardShortcut(.cancelAction)
                        Button("Сохранить") { save() }.buttonStyle(.borderedProminent).tint(tint.color)
                            .keyboardShortcut(.defaultAction).disabled(model.startupError != nil)
                    }
                }.padding(28)
            }.frame(width: 450)
        }.frame(height: 660)
        .background(.background)
        .onAppear { if let first = model.profiles.first { select(first) } }
        .onChange(of: link) { _ in confirmedAccess = nil; detectedValue = nil }
        .sheet(item: $discovery) { request in
            DiscoveryView(url: request.url) { rule, value in
                confirmedAccess = DashboardAccess(url: request.url, rule: rule)
                detectedValue = value
                notice = "Остаток выбран. Нажмите «Сохранить», чтобы подключить панель."
                error = nil
            }
        }
        .alert("Удалить панель?", isPresented: $confirmingRemoval) {
            Button("Удалить", role: .destructive) {
                guard let id = selectedID else { return }
                do {
                    try model.remove(id)
                    newPanel()
                    if let first = model.profiles.first { select(first) }
                } catch { self.error = error.localizedDescription }
            }
            Button("Отмена", role: .cancel) { }
        } message: { Text("Счётчик и сохранённая ссылка будут удалены. Токены на аккаунте останутся.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Ваши панели").font(.title3).fontWeight(.semibold)
                Text("\(model.profiles.count) подключено").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 8).padding(.top, 8)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.profiles) { profile in
                        Button { select(profile) } label: {
                            HStack(spacing: 9) {
                                PanelBadge(name: profile.name, tint: profile.tint, size: 30)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name).fontWeight(.medium).lineLimit(1)
                                    Text(PanelProfile.intervalLabel(profile.interval)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(selectedID == profile.id ? profile.tint.color.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 11))
                        }.buttonStyle(.plain)
                    }
                }
            }
            Button { newPanel() } label: { Label("Добавить панель", systemImage: "plus") }
                .buttonStyle(.bordered).frame(maxWidth: .infinity)
            Text("Каждая панель видна отдельно в строке меню.")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6)
        }.padding(14).frame(width: 205).background(.ultraThinMaterial)
    }

    private func fieldTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
    }
    private func select(_ profile: PanelProfile) {
        selectedID = profile.id; name = profile.name; interval = profile.interval
        tint = profile.tint; link = ""; error = nil; notice = nil
        confirmedAccess = nil; detectedValue = nil
        thresholdText = profile.lowBalanceThreshold.map { String(format: "%.0f", $0) } ?? ""
    }
    private func newPanel() {
        selectedID = nil; name = ""; link = ""; interval = 60
        tint = PanelTint.allCases[model.profiles.count % PanelTint.allCases.count]
        error = nil; notice = nil; confirmedAccess = nil; detectedValue = nil; thresholdText = ""
    }

    private func discover() {
        do {
            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
            let url: URL
            if !trimmed.isEmpty { url = try DashboardCredential.validate(trimmed) }
            else if let id = selectedID, let stored = try DashboardCredential.loadAccess(account: id) { url = stored.url }
            else { throw ProfileError.missingURL }
            discovery = DiscoveryRequest(url: url)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let currentURL = try DashboardCredential.validate(trimmed)
                if confirmedAccess?.url.absoluteString != currentURL.absoluteString {
                    confirmedAccess = nil; detectedValue = nil
                    discover()
                    return
                }
            }
            let threshold = try LowBalancePolicy.parseThreshold(thresholdText)
            try model.save(id: selectedID, name: name, interval: interval, tint: tint,
                           link: confirmedAccess?.url.absoluteString ?? trimmed, rule: confirmedAccess?.rule,
                           lowBalanceThreshold: threshold)
            if selectedID == nil { selectedID = model.profiles.last?.id }
            name = PanelProfile.normalizedName(name)
            link = ""; confirmedAccess = nil; detectedValue = nil
            error = nil; notice = "Сохранено. Счётчик уже в строке меню."
        } catch { self.error = error.localizedDescription; notice = nil }
    }
}

private struct DiscoveryRequest: Identifiable {
    let id = UUID()
    let url: URL
}
