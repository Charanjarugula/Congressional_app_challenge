import SwiftUI

/// The hit a hit chat is about, pinned under the header.
struct PinnedHitBar: View {
    let hit: Hit
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(hit.dayText)
                    Text(hit.clockText)
                }
                .font(CourtlyFont.rounded(15))
                .foregroundStyle(CourtlyColor.ink)
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(hit.format.shortTitle) · \(hit.court.shortName)")
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                        .lineLimit(2)
                    Text(hit.statusKind.title)
                        .font(CourtlyFont.captionSemibold)
                        .foregroundStyle(hit.statusKind == .confirmed ? CourtlyColor.green : CourtlyColor.secondary)
                }
                Spacer(minLength: 8)
                ChevronMark()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
}
