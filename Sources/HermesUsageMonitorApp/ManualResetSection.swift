import Foundation
import HermesUsageCore
import SwiftUI

struct ManualResetDisplayModel: Equatable {
    let countLabel: String?
    let title: String
    let statusLabel: String?
    let applicabilityLabel: String?
    let expirationLabel: String?
    let isStale: Bool

    init(
        state: ManualResetRefreshState,
        locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) {
        switch state {
        case .unavailable:
            countLabel = nil
            title = "Stato reset non disponibile"
            statusLabel = nil
            applicabilityLabel = nil
            expirationLabel = nil
            isStale = false
        case let .live(summary):
            countLabel = Self.countLabel(summary.availableCount)
            title = Self.title(summary.availableCount)
            statusLabel = nil
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
        case let .stale(summary):
            countLabel = Self.countLabel(summary.availableCount)
            title = Self.title(summary.availableCount)
            statusLabel = "Non aggiornato"
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
        }
    }

    private static func countLabel(_ count: Int) -> String {
        count == 1 ? "1 disponibile" : "\(count) disponibili"
    }

    private static func title(_ count: Int) -> String {
        switch count {
        case 0:
            return "Nessun Full reset disponibile"
        case 1:
            return "Full reset disponibile"
        default:
            return "Full reset disponibili"
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(.caption.weight(.semibold))

            if let statusLabel = model.statusLabel {
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(model.isStale ? Color.orange : Color.secondary)
            }

            if let applicabilityLabel = model.applicabilityLabel {
                Text(applicabilityLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let expirationLabel = model.expirationLabel {
                Text(expirationLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
