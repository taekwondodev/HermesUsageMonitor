import HermesUsageCore
import Observation
import SwiftUI

@main
struct HermesUsageMonitorApp: App {
    @State private var model = UsageViewModel()

    init() {
        let model = UsageViewModel()
        _model = State(initialValue: model)
        Task { await model.startAutomaticRefresh() }
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(model: model)
        } label: {
            Image(systemName: "sparkles")
                .accessibilityLabel("AI usage")
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
@Observable
private final class UsageViewModel {
    var subscriptions: [SubscriptionQuota]
    var availability: RefreshAvailability = .waiting
    var updatedAt: QuotaTimestamp?
    var accountingBySubscription: [Subscription: [LocalAccounting]] = [:]
    var accountingAvailability: AccountingAvailability = .waiting

    private let service: ProfileQuotaRefreshService
    private let accountingService: LocalAccountingService

    init() {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".hermes", isDirectory: true)
        service = ProfileQuotaRefreshService(hermesHome: hermesHome)
        accountingService = LocalAccountingService(source: HermesAccountingReader())
        subscriptions = Subscription.allCases.map {
            SubscriptionQuota(subscription: $0, result: .unavailable(.sourceMissing))
        }
    }

    func refresh() async {
        let state = await service.refresh()
        subscriptions = state.subscriptions
        availability = state.availability
        updatedAt = state.updatedAt
        do {
            accountingBySubscription = try accountingService.readGroupedBySubscription()
            accountingAvailability = .available
        } catch let error as LocalAccountingReadError {
            accountingBySubscription = [:]
            accountingAvailability = .unavailable(error.label)
        } catch {
            accountingBySubscription = [:]
            accountingAvailability = .unavailable("La contabilità locale non è leggibile.")
        }
    }

    func startAutomaticRefresh() async {
        await refresh()
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: ProfileQuotaRefreshService.defaultInterval)
            } catch {
                return
            }
            await refresh()
        }
    }
}

private struct UsagePopoverView: View {
    let model: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .padding(.vertical, 10)

            VStack(spacing: 10) {
                ForEach(model.subscriptions) { subscription in
                    SubscriptionCard(
                        subscription: subscription,
                        accounting: model.accountingBySubscription[subscription.subscription] ?? [],
                        accountingAvailability: model.accountingAvailability
                    )
                }
            }

            Divider()
                .padding(.vertical, 10)

            Label(
                model.availability.label,
                systemImage: "clock.arrow.circlepath"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if let updatedAt = model.updatedAt {
                Text("Aggiornato \(updatedAt.date, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Usage")
                    .font(.title3.weight(.semibold))

                Text("3 abbonamenti")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Aggiorna", systemImage: "arrow.clockwise") {
                Task { await model.refresh() }
            }
            .labelStyle(.iconOnly)
            .accessibilityLabel("Aggiorna dati Hermes")
        }
    }
}

private struct SubscriptionCard: View {
    let subscription: SubscriptionQuota
    let accounting: [LocalAccounting]
    let accountingAvailability: AccountingAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: subscription.subscription.symbol)
                    .frame(width: 20)
                    .foregroundStyle(.tint)

                Text(subscription.subscription.displayName)
                    .font(.headline)

                Spacer()

                Text(subscription.statusLabel)
                    .font(.caption)
                    .foregroundStyle(subscription.statusColor)
            }

            switch subscription.result {
            case let .snapshot(snapshot):
                snapshotContent(snapshot)
            case let .unavailable(reason):
                unavailableContent(reason)
            }

            if !accounting.isEmpty {
                AccountingSection(accounting: accounting)
            } else if case let .unavailable(reason) = accountingAvailability {
                Text("Contabilità locale non disponibile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func snapshotContent(_ snapshot: QuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.windows.sorted(by: isHigherRisk), id: \.kind) { window in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(window.label)
                            .font(.subheadline.weight(.medium))

                        Spacer()

                        Text("\(window.usedPercent, specifier: "%.0f")%")
                            .font(.subheadline.monospacedDigit())
                    }

                    ProgressView(value: window.usedPercent, total: 100)
                        .tint(color(for: window, freshness: snapshot.freshness))
                        .accessibilityValue("\(window.usedPercent, specifier: "%.0f") percent used")

                    if let resetAt = window.resetAt?.at.date {
                        Text("Reset \(resetAt, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Reset non disponibile")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(freshnessLabel(snapshot.freshness))
                .font(.caption2)
                .foregroundStyle(snapshot.freshness == .stale ? Color.orange : Color.gray)

            Text("Snapshot acquisito \(snapshot.capturedAt.date, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func unavailableContent(_ reason: QuotaUnavailableReason) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Quota non disponibile")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(reason.label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func isHigherRisk(_ lhs: QuotaWindow, _ rhs: QuotaWindow) -> Bool {
        if lhs.usedPercent != rhs.usedPercent {
            return lhs.usedPercent > rhs.usedPercent
        }
        return (lhs.resetAt?.at.date ?? .distantFuture) < (rhs.resetAt?.at.date ?? .distantFuture)
    }

    private func color(for window: QuotaWindow, freshness: QuotaFreshness) -> Color {
        guard freshness != .stale else { return .gray }
        if window.usedPercent >= 100 { return .red }
        if window.usedPercent >= 80 { return .orange }
        return .green
    }

    private func freshnessLabel(_ freshness: QuotaFreshness) -> String {
        switch freshness {
        case .live:
            return "Dato live da Hermes"
        case .persisted:
            return "Snapshot Hermes persistito"
        case .stale:
            return "Dato vecchio · non verificato"
        }
    }
}

private struct AccountingSection: View {
    let accounting: [LocalAccounting]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Uso osservato da Hermes", systemImage: "chart.bar.doc.horizontal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(Array(accounting.enumerated()), id: \.offset) { _, item in
                AccountingDetail(item: item)
            }
        }
        .padding(8)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct AccountingDetail: View {
    let item: LocalAccounting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let tokens = item.tokens {
                HStack(spacing: 4) {
                    if let input = tokens.input { Text("Input: \(input)") }
                    if let output = tokens.output { Text("Output: \(output)") }
                }
                .font(.caption2)
            }
            if let requests = item.requests {
                Text("Richieste: \(requests)")
                    .font(.caption2)
            }
            if !item.models.isEmpty {
                Text("Modelli: \(item.models.joined(separator: ", "))")
                    .font(.caption2)
            }
            if let cost = item.cost {
                Text("Costo: \(cost.amount.description) \(cost.currency)")
                    .font(.caption2)
            }
            if let provider = item.provider {
                Text(provider)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private enum AccountingAvailability: Equatable {
    case waiting
    case available
    case unavailable(String)
}

private extension Subscription {
    var displayName: String {
        switch self {
        case .nousPortal:
            return "Nous Portal"
        case .opencodeGo:
            return "OpenCode Go"
        case .chatGPT:
            return "ChatGPT"
        }
    }

    var symbol: String {
        switch self {
        case .nousPortal:
            return "globe.americas.fill"
        case .opencodeGo:
            return "chevron.left.forwardslash.chevron.right"
        case .chatGPT:
            return "bubble.left.and.bubble.right.fill"
        }
    }
}

private extension LocalAccountingReadError {
    var label: String {
        switch self {
        case .sourceMissing:
            return "Hermes non ha ancora prodotto uno snapshot accounting."
        case .sourceUnreadable:
            return "La sorgente accounting Hermes non è leggibile."
        case .malformedData:
            return "Lo snapshot accounting Hermes non è valido."
        case .unsupportedVersion:
            return "Versione accounting non supportata."
        }
    }
}

private extension SubscriptionQuota {
    var hasAvailableSnapshot: Bool {
        if case .snapshot = result { return true }
        return false
    }

    var statusLabel: String {
        switch result {
        case let .snapshot(snapshot):
            if snapshot.freshness == .stale { return "Stale" }
            if snapshot.windows.contains(where: { $0.usedPercent >= 100 }) { return "Esaurita" }
            return "Attiva"
        case .unavailable:
            return "In attesa"
        }
    }

    var statusColor: Color {
        switch result {
        case let .snapshot(snapshot) where snapshot.freshness == .stale:
            return .orange
        case let .snapshot(snapshot) where snapshot.windows.contains(where: { $0.usedPercent >= 100 }):
            return .red
        case .snapshot:
            return .green
        case .unavailable:
            return .secondary
        }
    }
}

private extension RefreshAvailability {
    var label: String {
        switch self {
        case .live:
            return "Dati osservati da Hermes"
        case .offline:
            return "Hermes offline · ultimo snapshot mantenuto"
        case .waiting:
            return "In attesa dei dati di Hermes"
        }
    }
}

private extension QuotaUnavailableReason {
    var label: String {
        switch self {
        case .sourceMissing:
            return "Usa Hermes Agent per generare il primo snapshot."
        case .sourceUnreadable:
            return "La sorgente Hermes non è leggibile."
        case .malformedSnapshot:
            return "Lo snapshot Hermes non è valido."
        case .unsupportedVersion:
            return "Versione dello snapshot non supportata."
        }
    }
}
