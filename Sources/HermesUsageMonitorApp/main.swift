import SwiftUI

@main
struct HermesUsageMonitorApp: App {
    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView()
        } label: {
            Image(systemName: "sparkles")
                .accessibilityLabel("AI usage")
        }
        .menuBarExtraStyle(.window)
    }
}

private struct UsagePopoverView: View {
    private let subscriptions = Subscription.preview

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()
                .padding(.vertical, 10)

            VStack(spacing: 10) {
                ForEach(subscriptions) { subscription in
                    SubscriptionCard(subscription: subscription)
                }
            }

            Divider()
                .padding(.vertical, 10)

            HStack {
                Label("In attesa dei dati di Hermes", systemImage: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("Mai aggiornato")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("AI Usage")
                .font(.title3.weight(.semibold))

            Text("3 abbonamenti")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SubscriptionCard: View {
    let subscription: Subscription

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: subscription.symbol)
                    .frame(width: 20)
                    .foregroundStyle(.tint)

                Text(subscription.name)
                    .font(.headline)

                Spacer()

                Text("Dati in attesa")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Quota non disponibile")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Usa Hermes Agent per generare il primo snapshot.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct Subscription: Identifiable {
    let id: String
    let name: String
    let symbol: String

    static let preview = [
        Subscription(id: "nous-portal", name: "Nous Portal", symbol: "globe.americas.fill"),
        Subscription(id: "opencode-go", name: "OpenCode Go", symbol: "chevron.left.forwardslash.chevron.right"),
        Subscription(id: "chatgpt", name: "ChatGPT", symbol: "bubble.left.and.bubble.right.fill")
    ]
}
