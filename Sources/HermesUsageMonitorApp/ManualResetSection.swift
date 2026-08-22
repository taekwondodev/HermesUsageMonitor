import Foundation
import HermesUsageCore
import SwiftUI

enum ManualResetDesignToken {
    static let contentBackground = Color.primary.opacity(0.06)
    static let expirationLabelColor = Color(nsColor: .tertiaryLabelColor)
    static let redeemTint = Color(
        red: 0.188_235_30,
        green: 0.819_607_85,
        blue: 0.345_098_05
    )
    static let cornerRadius: CGFloat = 8
}

struct ManualResetDisplayModel: Equatable {
    let headerCountLabel: String?
    let primaryLabel: String
    let applicabilityLabel: String?
    let expirationLabel: String?
    let isStale: Bool
    let isRedeemEnabled: Bool

    init(
        state: ManualResetRefreshState,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        switch state {
        case .unavailable:
            headerCountLabel = nil
            primaryLabel = "Stato reset non disponibile"
            applicabilityLabel = nil
            expirationLabel = nil
            isStale = false
            isRedeemEnabled = false
        case let .live(summary):
            headerCountLabel = Self.countLabel(summary.availableCount)
            primaryLabel = summary.availableCount == 0
                ? "Full reset non disponibile"
                : "Full reset disponibile"
            applicabilityLabel = summary.availableCount == 0
                ? nil
                : summary.isApplicable ? "Utilizzabile ora" : "Non utilizzabile ora"
            expirationLabel = summary.availableCount == 0
                ? nil
                : Self.expirationLabel(
                    summary.expiration,
                    locale: locale,
                    timeZone: timeZone
                )
            isStale = false
            isRedeemEnabled = summary.hasActionableCredit && summary.isApplicable
        case let .stale(summary):
            headerCountLabel = Self.countLabel(summary.availableCount)
            primaryLabel = summary.availableCount == 0
                ? "Full reset non disponibile"
                : "Full reset disponibile"
            applicabilityLabel = summary.availableCount == 0
                ? nil
                : summary.isApplicable
                    ? "Utilizzabile all’ultimo aggiornamento"
                    : "Non utilizzabile all’ultimo aggiornamento"
            expirationLabel = summary.availableCount == 0
                ? nil
                : Self.expirationLabel(
                    summary.expiration,
                    locale: locale,
                    timeZone: timeZone
                )
            isStale = true
            isRedeemEnabled = false
        }
    }

    private static func countLabel(_ count: Int) -> String {
        count == 1 ? "1 disponibile" : "\(count) disponibili"
    }

    private static func expirationLabel(
        _ expiration: ManualResetExpiration,
        locale: Locale,
        timeZone: TimeZone
    ) -> String? {
        switch expiration {
        case let .dated(timestamp):
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = "d/M"
            return "Scade il \(formatter.string(from: timestamp.date))"
        case .doesNotExpire:
            return "Nessuna scadenza"
        case .unavailable:
            return "Scadenza non disponibile"
        }
    }
}

struct ManualResetSection: View {
    let state: ManualResetRefreshState
    let flow: ManualResetRedemptionFlowState
    let canRedeem: Bool
    let onRedeem: () -> Void
    let onConfirmRedeem: () -> Void
    let onRetryRedeem: () -> Void
    let onDismiss: () -> Void

    private var model: ManualResetDisplayModel {
        ManualResetDisplayModel(state: state)
    }

    private var expectedRemainingCount: Int? {
        guard case let .live(summary) = state else { return nil }
        return max(0, summary.availableCount - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.primaryLabel)
                        .font(.caption.weight(.semibold))

                    if model.isStale {
                        Text("Non aggiornato")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                    }

                    if let applicabilityLabel = model.applicabilityLabel {
                        Text(applicabilityLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if flow == .success {
                        Text("Reset riscattato")
                            .font(.caption2)
                            .foregroundStyle(ManualResetDesignToken.redeemTint)
                    } else if flow == .unverified && !flow.isIdle {
                        Text("Esito non confermato")
                            .font(.caption2)
                            .foregroundStyle(Color.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Riscatta", action: onRedeem)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(ManualResetDesignToken.redeemTint)
                    .disabled(!canRedeem)
                    .accessibilityHint("Riscatta il Full reset disponibile")
            }

            if let expirationLabel = model.expirationLabel {
                Divider()

                Text(expirationLabel)
                    .font(.caption2)
                    .foregroundStyle(ManualResetDesignToken.expirationLabelColor)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: ManualResetDesignToken.cornerRadius)
                .fill(ManualResetDesignToken.contentBackground)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .confirmationDialog(
            "Riscattare un Full reset?",
            isPresented: Binding(
                get: { flow == .confirming },
                set: { if !$0 { onDismiss() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Riscatta") { onConfirmRedeem() }
            Button("Annulla", role: .cancel) { onDismiss() }
        } message: {
            Text(confirmationMessage)
        }
        .alert(
            "Esito riscatto non confermato",
            isPresented: Binding(
                get: { flow == .unverified && !flow.isRedeeming },
                set: { if !$0 { onDismiss() } }
            )
        ) {
            Button("Riprova") { onRetryRedeem() }
            Button("Chiudi", role: .cancel, action: onDismiss)
        } message: {
            Text("Il provider non conferma se il reset è stato consumato. Un nuovo riscatto è bloccato finché lo stato non viene rinfrescato.")
        }
        .alert(
            rejectedTitle,
            isPresented: Binding(
                get: { flow.showsRejected && !flow.isRedeeming },
                set: { if !$0 { onDismiss() } }
            )
        ) {
            Button("Chiudi", role: .cancel, action: onDismiss)
        } message: {
            Text(rejectedMessage)
        }
    }

    private var rejectedTitle: String {
        flow == .notConsumed ? "Riscatto non effettuato" : "Riscatto non riuscito"
    }

    private var rejectedMessage: String {
        flow == .notConsumed
            ? "Il provider non ha consumato il reset: non c'era un reset da applicare. Nessun credit è stato speso."
            : "Il riscatto non è andato a buon fine. Nessun credit è stato speso."
    }

    private var confirmationMessage: String {
        let remaining = expectedRemainingCount.map { "Rimarranno \($0) disponibili." } ??
            "Un Full reset verrà consumato."
        return "Verrà consumato un Full reset. \(remaining)"
    }
}
