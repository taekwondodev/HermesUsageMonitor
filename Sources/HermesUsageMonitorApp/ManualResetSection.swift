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

    private var model: ManualResetDisplayModel {
        ManualResetDisplayModel(state: state)
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
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Riscatta") {}
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(ManualResetDesignToken.redeemTint)
                    .disabled(!model.isRedeemEnabled)
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
    }
}
