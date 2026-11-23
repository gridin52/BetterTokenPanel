import AppKit
import SwiftUI

struct PanelBadge: View {
    let name: String
    let tint: PanelTint
    var size: CGFloat = 36
    var body: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(.system(size: size * 0.43, weight: .bold, design: .rounded))
            .foregroundStyle(tint.color)
            .frame(width: size, height: size)
            .background(tint.color.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    let profileID: String
    private var profile: PanelProfile? { model.profiles.first { $0.id == profileID } }

    var body: some View {
        Group {
            if let profile = profile, let monitor = model.monitor(for: profileID) {
                content(profile, monitor)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "square.stack.3d.up").font(.system(size: 30)).foregroundStyle(.blue)
                    Text("Токены под рукой").font(.title2).fontWeight(.semibold)
                    Text(model.startupError ?? "Добавьте Claude, Codex или другую HTTPS-панель. У каждой будет свой счётчик в строке меню.")
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("Добавить панель") { model.settings?() }.buttonStyle(.borderedProminent)
                    if model.startupError != nil {
                        Button("Повторить подключение") { model.retryMigration(); model.start() }
                    }
                    Button("Выйти") { model.quit?() }.buttonStyle(.link)
                }.padding(28).frame(width: 340)
            }
        }
    }

    private func content(_ profile: PanelProfile, _ monitor: BalanceMonitor) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 11) {
                PanelBadge(name: profile.name, tint: profile.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name).font(.headline)
                    Text("Баланс токенов").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if monitor.loading { ProgressView().controlSize(.small) }
                else {
                    Label(monitor.hasError ? "Нет связи" : "Подключено", systemImage: monitor.hasError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.caption2).foregroundStyle(monitor.hasError ? Color.orange : Color.secondary)
                }
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Осталось токенов").font(.subheadline).foregroundStyle(.secondary)
                    Text(monitor.balance.map { Balance.compact($0.remaining) } ?? "—")
                        .font(.system(size: 42, weight: .semibold, design: .rounded))
                        .tracking(-1.5).monospacedDigit().textSelection(.enabled)
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(model.isLow(profile) ? Color.orange : Color.primary)
                    if let balance = monitor.balance {
                        Text("Обновлено \(balance.fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if let balance = monitor.balance, let total = balance.total, total > 0 {
                    balanceRing(balance.remaining / total, tint: profile.tint)
                }
            }.padding(.vertical, 5)
            if let balance = monitor.balance, balance.spent != nil || balance.total != nil {
                HStack(spacing: 0) {
                    metric("Потрачено", balance.spent)
                    Spacer()
                    Rectangle().fill(.quaternary).frame(width: 1, height: 30)
                    Spacer()
                    metric("Начислено", balance.total)
                }.padding(14).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            }
            if model.isLow(profile), let threshold = profile.lowBalanceThreshold {
                Label("Ниже порога \(Balance.compact(threshold)) токенов", systemImage: "bell.badge.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            if monitor.hasError || monitor.balance == nil {
                Label(monitor.message, systemImage: monitor.hasError ? "exclamationmark.triangle" : "clock")
                    .font(.caption).foregroundStyle(monitor.hasError ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Label("Каждые \(PanelProfile.intervalLabel(profile.interval))", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { model.settings?() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("Панели и настройки")
            }
            HStack(spacing: 10) {
                Button { monitor.refresh() } label: {
                    Label("Обновить", systemImage: "arrow.clockwise").frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(profile.tint.color).disabled(monitor.loading)
                Button {
                    if let url = monitor.dashboardURL { NSWorkspace.shared.open(url) }
                } label: {
                    Image(systemName: "arrow.up.right.square").frame(width: 22)
                }.buttonStyle(.bordered).disabled(monitor.dashboardURL == nil).help("Открыть панель в браузере")
            }.controlSize(.large)
            HStack {
                Text("BetterTokenPanel").font(.caption2).foregroundStyle(.tertiary)
                Spacer()
                Button("Выйти") { model.quit?() }.font(.caption2).buttonStyle(.link).tint(.secondary)
            }
        }.padding(22).frame(width: 360)
    }

    private func balanceRing(_ raw: Double, tint: PanelTint) -> some View {
        let fraction = min(max(raw, 0), 1)
        return ZStack {
            Circle().stroke(tint.color.opacity(0.12), lineWidth: 6)
            Circle().trim(from: 0, to: fraction)
                .stroke(tint.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(String(format: "%.0f%%", fraction * 100)).font(.system(.caption, design: .rounded).weight(.semibold)).monospacedDigit()
        }.frame(width: 62, height: 62).accessibilityLabel("Осталось \(Int(fraction * 100)) процентов")
    }

    private func metric(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.map { Balance.compact($0) } ?? "—")
                .font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
        }
    }
}
