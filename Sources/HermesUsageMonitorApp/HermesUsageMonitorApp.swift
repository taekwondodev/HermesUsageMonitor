import HermesUsageCore
import Observation
import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers

@main
struct HermesUsageMonitorApp: App {
    @State private var model = UsageViewModel()

    init() {
        guard SingleInstanceGuard.acquire() else {
            exit(EXIT_SUCCESS)
        }

        let model = UsageViewModel()
        _model = State(initialValue: model)
        Task { await NotificationAuthorizationCoordinator.requestOnLaunchIfNeeded() }
        model.startAutomaticRefresh()
    }

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(
                model: model,
                onTerminate: {
                    AppShutdownCoordinator(
                        stopRefresh: model.stopAutomaticRefresh,
                        terminate: { NSApplication.shared.terminate(nil) }
                    ).shutdown()
                }
            )
        } label: {
            Label {
                Text("AI usage")
            } icon: {
                HermesMenuBarIcon()
            }
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
    private let resetService: QuotaResetNotificationService
    private let accountingService: LocalAccountingService
    private var automaticRefreshTask: Task<Void, Never>? = nil
    private var resetRefreshTask: Task<Void, Never>? = nil
    private var resetRetryTask: Task<Void, Never>? = nil
    private var inFlightRefresh: Task<SubscriptionRefreshState, Never>?
    var pendingQuotaRefreshWindows: Set<QuotaWindowReference> = []

    private enum RefreshTrigger {
        case manual
        case automatic
        case scheduled
        case retry
    }

    init() {
        let hermesHome = ProcessInfo.processInfo.environment["HERMES_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".hermes", isDirectory: true)
        let hermesRoot = hermesHome.deletingLastPathComponent().lastPathComponent == "profiles"
            ? hermesHome
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            : hermesHome
        service = ProfileQuotaRefreshService(hermesHome: hermesHome)
        resetService = QuotaResetNotificationService(notifier: MacOSQuotaResetNotifier())
        accountingService = LocalAccountingService(source: HermesStateDBAccountingReader(hermesHome: hermesRoot))
        subscriptions = Subscription.allCases.map {
            SubscriptionQuota(subscription: $0, result: .unavailable(.sourceMissing))
        }
    }

    func refresh() async {
        await refresh(trigger: .manual)
    }

    private func refresh(trigger: RefreshTrigger) async {
        if trigger != .retry {
            resetRetryTask?.cancel()
            resetRetryTask = nil
        }

        let state: SubscriptionRefreshState
        if let inFlightRefresh {
            state = await inFlightRefresh.value
        } else {
            let task = Task { await service.refresh() }
            inFlightRefresh = task
            state = await task.value
            inFlightRefresh = nil
        }

        subscriptions = state.subscriptions
        availability = state.availability
        updatedAt = state.updatedAt
        await resetService.process(state)
        switch accountingService.readGroupedBySubscription() {
        case let .available(grouped):
            accountingBySubscription = grouped
            accountingAvailability = .available
        case let .unavailable(reason):
            accountingBySubscription = [:]
            accountingAvailability = .unavailable(reason.label)
        }

        pendingQuotaRefreshWindows.removeAll()
        scheduleResetRefresh(from: state)
    }

    private func scheduleResetRefresh(from state: SubscriptionRefreshState) {
        resetRefreshTask?.cancel()
        resetRefreshTask = nil

        guard let resetAt = QuotaRefreshSchedule.nextLiveReset(in: state, now: Date()) else {
            return
        }

        let delay = max(0, resetAt.timeIntervalSinceNow)
        resetRefreshTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }

                let attemptedWindows = QuotaRefreshSchedule.expiredLiveWindows(
                    in: state,
                    now: Date()
                )
                guard !attemptedWindows.isEmpty else { return }

                self.pendingQuotaRefreshWindows.formUnion(attemptedWindows)
                try await Task.sleep(for: .seconds(QuotaRefreshSchedule.postResetDelay))
                guard !Task.isCancelled else { return }

                await self.refresh(trigger: .scheduled)
                if QuotaRefreshSchedule.shouldRetry(
                    state: self.currentRefreshState,
                    attemptedWindows: attemptedWindows,
                    now: Date()
                ) {
                    self.scheduleResetRetry(for: attemptedWindows)
                }
            } catch {
                return
            }
        }
    }

    private func scheduleResetRetry(for windows: Set<QuotaWindowReference>) {
        resetRetryTask?.cancel()
        resetRetryTask = Task { [weak self] in
            do {
                guard let retryDelay = QuotaRefreshSchedule.nextRetryDelay(after: 0) else { return }
                try await Task.sleep(for: retryDelay)
                guard !Task.isCancelled, let self else { return }
                self.pendingQuotaRefreshWindows.formUnion(windows)
                await self.refresh(trigger: .retry)
            } catch {
                return
            }
        }
    }

    private var currentRefreshState: SubscriptionRefreshState {
        SubscriptionRefreshState(
            subscriptions: subscriptions,
            availability: availability,
            updatedAt: updatedAt
        )
    }

    func startAutomaticRefresh() {
        guard automaticRefreshTask == nil else { return }
        automaticRefreshTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh(trigger: .automatic)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: ProfileQuotaRefreshService.defaultInterval)
                } catch {
                    return
                }
                await self.refresh(trigger: .automatic)
            }
        }
    }

    func stopAutomaticRefresh() {
        automaticRefreshTask?.cancel()
        automaticRefreshTask = nil
        resetRefreshTask?.cancel()
        resetRefreshTask = nil
        resetRetryTask?.cancel()
        resetRetryTask = nil
    }
}

private struct UsagePopoverView: View {
    let model: UsageViewModel
    let onTerminate: () -> Void
    @State private var expandedSubscriptions: Set<Subscription> = []
    @State private var orderedSubscriptions = SubscriptionOrderStore.load()
    @State private var draggedSubscription: Subscription?
    @State private var dropTarget: Subscription?

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .padding(.vertical, 10)

            VStack(spacing: 10) {
                ForEach(displaySubscriptions) { subscription in
                    SubscriptionCard(
                        subscription: subscription,
                        accounting: model.accountingBySubscription[subscription.subscription] ?? [],
                        accountingAvailability: model.accountingAvailability,
                        pendingQuotaRefreshWindows: model.pendingQuotaRefreshWindows,
                        isAccountingExpanded: Binding(
                            get: { expandedSubscriptions.contains(subscription.subscription) },
                            set: { expanded in
                                setAccounting(
                                    for: subscription.subscription,
                                    expanded: expanded
                                )
                            }
                        ),
                        onMove: moveSubscription
                    )
                    .onDrag {
                        draggedSubscription = subscription.subscription
                        return NSItemProvider(object: subscription.subscription.rawValue as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        isTargeted: Binding(
                            get: { dropTarget == subscription.subscription },
                            set: { targeted in
                                dropTarget = targeted ? subscription.subscription : nil
                            }
                        )
                    ) { _, _ in
                        completeDrop(on: subscription.subscription)
                    }
                    .overlay {
                        if dropTarget == subscription.subscription {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.accentColor, lineWidth: 2)
                                .padding(1)
                                .allowsHitTesting(false)
                        }
                    }
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
                Text("\(model.availability == .offline ? "Controllato" : "Aggiornato") \(updatedAt.date, style: .relative)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 380)
        .frame(minHeight: PopoverLayout.minimumHeight, idealHeight: PopoverLayout.idealHeight, maxHeight: PopoverLayout.maximumHeight)
    }

    private func setAccounting(for subscription: Subscription, expanded: Bool) {
        if expanded {
            expandedSubscriptions.insert(subscription)
        } else {
            expandedSubscriptions.remove(subscription)
        }
    }

    private var displaySubscriptions: [SubscriptionQuota] {
        let bySubscription = Dictionary(uniqueKeysWithValues: model.subscriptions.map {
            ($0.subscription, $0)
        })
        let ordered = orderedSubscriptions.compactMap { bySubscription[$0] }
        let missing = model.subscriptions.filter { !orderedSubscriptions.contains($0.subscription) }
        return ordered + missing
    }

    private func moveSubscription(_ subscription: Subscription, by offset: Int) {
        let updatedOrder = SubscriptionOrderStore.moved(
            orderedSubscriptions,
            visibleItems: displaySubscriptions.map(\.subscription),
            item: subscription,
            by: offset
        )
        guard updatedOrder != orderedSubscriptions else { return }
        orderedSubscriptions = updatedOrder
        saveSubscriptionOrder()
    }

    private func saveSubscriptionOrder() {
        SubscriptionOrderStore.save(orderedSubscriptions)
    }

    private func completeDrop(on target: Subscription) -> Bool {
        guard let dragged = draggedSubscription,
              dragged != target,
              let draggedIndex = displaySubscriptions.firstIndex(where: { $0.subscription == dragged }),
              let targetIndex = displaySubscriptions.firstIndex(where: { $0.subscription == target }) else {
            draggedSubscription = nil
            dropTarget = nil
            return false
        }

        orderedSubscriptions = SubscriptionOrderStore.movedBefore(
            orderedSubscriptions,
            visibleItems: displaySubscriptions.map(\.subscription),
            item: dragged,
            target: target
        )
        if draggedIndex != targetIndex {
            saveSubscriptionOrder()
        }
        draggedSubscription = nil
        dropTarget = nil
        return true
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

            Button("Chiudi HermesUsageMonitor", systemImage: "power", action: onTerminate)
                .labelStyle(.iconOnly)
                .foregroundStyle(.primary)
                .accessibilityLabel("Chiudi HermesUsageMonitor")
                .help("Chiudi HermesUsageMonitor")
        }
    }
}

private struct SubscriptionCard: View {
    let subscription: SubscriptionQuota
    let accounting: [LocalAccounting]
    let accountingAvailability: AccountingAvailability
    let pendingQuotaRefreshWindows: Set<QuotaWindowReference>
    @Binding var isAccountingExpanded: Bool
    let onMove: (Subscription, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SubscriptionIdentityIcon(subscription: subscription.subscription)

                Text(subscription.subscription.displayName)
                    .font(.headline)

                Spacer()

                Menu {
                    Button("Sposta prima") {
                        onMove(subscription.subscription, -1)
                    }
                    Button("Sposta dopo") {
                        onMove(subscription.subscription, 1)
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Riordina \(subscription.subscription.displayName)")

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

            if accountingAvailability != .waiting {
                DisclosureGroup(
                    isExpanded: $isAccountingExpanded
                ) {
                    AccountingSection(
                        accounting: accounting,
                        accountingAvailability: accountingAvailability
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Uso osservato da Hermes", systemImage: "umbrella.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                        if resetAt <= Date() {
                            let reference = QuotaWindowReference(
                                subscription: subscription.subscription,
                                kind: window.kind
                            )
                            Text(
                                pendingQuotaRefreshWindows.contains(reference)
                                    ? "Aggiornamento quota..."
                                    : "Quota non disponibile"
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        } else {
                            Text("Reset \(resetAt, style: .relative)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
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
    let accountingAvailability: AccountingAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !accounting.isEmpty {
                ForEach(Array(accounting.enumerated()), id: \.offset) { _, item in
                    AccountingDetail(item: item)
                }
            } else if case let .unavailable(reason) = accountingAvailability {
                Text("Contabilità locale non disponibile")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(8)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct HermesMenuBarIcon: View {
    var body: some View {
        if let image = Self.loadImage() {
            Image(nsImage: image)
        }
    }

    private static func loadImage() -> NSImage? {
        guard let image = NSImage(named: "HermesMenuBarIcon") else {
            return nil
        }
        let ratio = image.size.height / image.size.width
        image.isTemplate = true
        image.size.height = 15
        image.size.width = 15 / ratio
        return image
    }
}

private struct SubscriptionIdentityIcon: View {
    let subscription: Subscription

    var body: some View {
        switch subscription {
        case .nousPortal:
            icon(ProviderAssetCatalog.nousPortal)
        case .opencodeGo:
            icon(ProviderAssetCatalog.opencodeGo)
        case .chatGPT:
            icon(ProviderAssetCatalog.chatGPT)
        }
    }

    private func icon(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(.background)
            if let image = ProviderAssetCatalog.image(named: name) {
                Image(nsImage: image)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(1)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Icona provider non disponibile")
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(.quaternary, lineWidth: 0.5)
        }
        .accessibilityHidden(true)
    }
}

enum ProviderAssetCatalog {
    static let nousPortal = "NousPortalIcon"
    static let opencodeGo = "OpenCodeGoIcon"
    static let chatGPT = "ChatGPTIcon"

    static let all = [nousPortal, opencodeGo, chatGPT]

    static func image(named name: String) -> NSImage? {
        NSImage(named: name)
    }
}

enum PopoverLayout {
    static let minimumHeight: CGFloat = 500
    static let idealHeight: CGFloat = 500
    static let maximumHeight: CGFloat = 640
}

enum SubscriptionOrderStore {
    private static let key = "subscriptionOrder.v1"

    static func load(defaults: UserDefaults = .standard) -> [Subscription] {
        let rawValues = defaults.array(forKey: key) as? [String] ?? []
        return normalize(rawValues.compactMap(Subscription.init(rawValue:)))
    }

    static func save(_ order: [Subscription], defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: key)
    }

    static func normalize(_ order: [Subscription]) -> [Subscription] {
        var result: [Subscription] = []
        for subscription in order where !result.contains(subscription) {
            result.append(subscription)
        }
        for subscription in Subscription.allCases where !result.contains(subscription) {
            result.append(subscription)
        }
        return result
    }

    static func moved(
        _ order: [Subscription],
        visibleItems: [Subscription] = Subscription.allCases,
        item: Subscription,
        by offset: Int
    ) -> [Subscription] {
        guard let index = visibleItems.firstIndex(of: item) else { return order }
        let destination = min(max(index + offset, 0), visibleItems.count - 1)
        guard destination != index else { return order }
        let target = visibleItems[destination]
        var result = order
        result.removeAll { $0 == item }
        guard let targetIndex = result.firstIndex(of: target) else { return order }
        result.insert(item, at: destination > index ? targetIndex + 1 : targetIndex)
        return result
    }

    static func movedBefore(
        _ order: [Subscription],
        visibleItems: [Subscription],
        item: Subscription,
        target: Subscription
    ) -> [Subscription] {
        guard item != target,
              visibleItems.contains(item),
              visibleItems.contains(target) else { return order }
        var result = order
        result.removeAll { $0 == item }
        guard let targetIndex = result.firstIndex(of: target) else { return order }
        result.insert(item, at: targetIndex)
        return result
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

private extension LocalAccountingUnavailableReason {
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
        case .commandMissing:
            return "Il comando usage non è disponibile nella versione Hermes installata."
        case .authenticationFailed:
            return "Hermes non ha potuto autenticare la sorgente usage."
        case .endpointUnavailable:
            return "L'endpoint usage del provider non è raggiungibile."
        }
    }
}
