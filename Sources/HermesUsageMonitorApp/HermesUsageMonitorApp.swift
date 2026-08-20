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
    var uiNow = Date()

    private let service: ProfileQuotaRefreshService
    private let resetService: QuotaResetNotificationService
    private let accountingService: LocalAccountingService
    private var automaticRefreshTask: Task<Void, Never>? = nil
    private var uiTimerTask: Task<Void, Never>? = nil
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

    func startUITimer() {
        uiTimerTask?.cancel()
        uiNow = Date()
        uiTimerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self.uiNow = Date()
            }
        }
    }

    func stopUITimer() {
        uiTimerTask?.cancel()
        uiTimerTask = nil
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
        stopUITimer()
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
                        uiNow: model.uiNow,
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
                Text("\(model.availability == .offline ? "Controllato" : "Aggiornato") \(updatedAt.date, format: .dateTime.day().month().hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(width: 380)
        .frame(minHeight: PopoverLayout.minimumHeight, idealHeight: PopoverLayout.idealHeight, maxHeight: PopoverLayout.maximumHeight)
        .onAppear {
            model.startUITimer()
        }
        .onDisappear {
            model.stopUITimer()
        }
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

                Text("2 abbonamenti")
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
    let uiNow: Date
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
                        accounting: accounting
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    HStack {
                        Label("Uso osservato da Hermes", systemImage: "umbrella.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("30 giorni")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        if case .unavailable = accountingAvailability {
                            Text("Non disponibile")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
            ForEach(displayedWindows(from: snapshot), id: \.kind) { window in
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
                        if resetAt <= uiNow {
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
                            Text("Reset \(countdownLabel(until: resetAt))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Reset")
                                .accessibilityValue(countdownLabel(until: resetAt))
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

            Text("Snapshot acquisito \(QuotaTemporalPolicy.snapshotAgeLabel(capturedAt: snapshot.capturedAt.date, now: uiNow))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Snapshot acquisito")
                .accessibilityValue(
                    QuotaTemporalPolicy.snapshotAgeLabel(
                        capturedAt: snapshot.capturedAt.date,
                        now: uiNow
                    )
                )
        }
    }

    private func displayedWindows(from snapshot: QuotaSnapshot) -> [QuotaWindow] {
        QuotaWindowDisplayOrder.windows(
            for: subscription.subscription,
            windows: snapshot.windows
        )
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

    private func countdownLabel(until date: Date) -> String {
        let seconds = QuotaTemporalPolicy.secondsRemaining(until: date, now: uiNow)
        if seconds < 60 {
            return "tra \(seconds)s"
        }

        let minutes = (seconds + 59) / 60
        if minutes < 60 {
            return "tra \(minutes) min"
        }

        let hours = (minutes + 59) / 60
        if hours < 24 {
            return "tra \(hours) h"
        }

        let days = (hours + 23) / 24
        return "tra \(days) g"
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
            ForEach(AccountingDisplayBlock.blocks(from: accounting)) { block in
                AccountingDetail(block: block)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AccountingDisplayBlock: Equatable, Identifiable {
    let id: String
    let modelLabel: String
    let requestsLabel: String
    let inputLabel: String
    let outputLabel: String
    let costLabel: String

    static func blocks(from items: [LocalAccounting]) -> [AccountingDisplayBlock] {
        items.enumerated().map { itemIndex, item in
            AccountingDisplayBlock(
                id: "\(itemIndex)",
                modelLabel: item.models.isEmpty
                    ? "Modello non disponibile"
                    : item.models.joined(separator: ", "),
                requestsLabel: item.requests.map { "\($0) richieste" } ?? "Non disponibile",
                inputLabel: item.tokens?.input.map(String.init) ?? "Non disponibile",
                outputLabel: item.tokens?.output.map(String.init) ?? "Non disponibile",
                costLabel: item.cost.map { "\($0.amount.description) \($0.currency)" } ?? "Non disponibile"
            )
        }
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
    static let opencodeGo = "OpenCodeGoIcon"
    static let chatGPT = "ChatGPTIcon"

    static let all = [opencodeGo, chatGPT]

    static func image(named name: String) -> NSImage? {
        NSImage(named: name)
    }
}

enum PopoverLayout {
    static let minimumHeight: CGFloat = 500
    static let idealHeight: CGFloat = 560
    static let maximumHeight: CGFloat = 700
}

enum SubscriptionOrderStore {
    private static let key = "subscriptionOrder.v1"

    static func load(defaults: UserDefaults = .standard) -> [Subscription] {
        let rawValues = defaults.array(forKey: key) as? [String] ?? []
        let normalized = normalize(rawValues.compactMap(Subscription.init(rawValue:)))
        if rawValues != normalized.map(\.rawValue) {
            defaults.set(normalized.map(\.rawValue), forKey: key)
        }
        return normalized
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
    let block: AccountingDisplayBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.modelLabel)
                    .font(.caption.weight(.semibold))

                Spacer()

                Text(block.requestsLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                metric("Input", value: block.inputLabel)
                metric("Output", value: block.outputLabel)
                metric("Costo", value: block.costLabel)
            }
            .font(.caption2)
        }
        .padding(.vertical, 6)
    }

    private func metric(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
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
        case .opencodeGo:
            return "OpenCode Go"
        case .chatGPT:
            return "ChatGPT"
        }
    }

    var symbol: String {
        switch self {
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
