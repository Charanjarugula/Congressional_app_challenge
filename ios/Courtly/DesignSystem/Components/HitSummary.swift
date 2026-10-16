import SwiftUI

/// Shared visual hierarchy; dates and status still come from the live hit in its court's time zone.
struct HitSummary: View {
    let hit: Hit
    var showsHost = true
    @ScaledMetric(relativeTo: .title) private var timeSize = 30

    private var availabilityLabel: String {
        if hit.status == .cancelled { return "This hit is no longer happening" }
        if hit.status == .expired { return "This hit has expired" }
        if hit.status == .played { return "\(hit.durationMin) min · \(hit.format.shortTitle)" }
        return hit.spotsOpen > 0 ? "\(hit.durationMin) min · \(hit.spotsLabel) open" : "\(hit.durationMin) min · All set"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.dateText.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(CourtlyColor.blue)
                    Text(hit.clockText)
                        .font(.system(size: timeSize, weight: .bold))
                        .foregroundStyle(CourtlyColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                StatusPill(kind: hit.statusKind)
            }
            Text(hit.format.title)
                .font(.headline)
                .foregroundStyle(CourtlyColor.ink)
            Text(hit.courtLine)
                .font(.subheadline)
                .foregroundStyle(CourtlyColor.secondary)
            HStack(spacing: 8) {
                Image("CourtsideBall")
                    .renderingMode(.template)
                    .foregroundStyle(CourtlyColor.blue)
                    .frame(width: 20, height: 20)
                    .accessibilityHidden(true)
                Text(availabilityLabel)
                    .font(.footnote)
                    .foregroundStyle(CourtlyColor.secondary)
            }
            if showsHost {
                HStack(spacing: 8) {
                    PlayerAvatar(card: hit.host, size: 28)
                    Text(hit.host.displayName)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(CourtlyColor.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
