import SwiftUI

/// Who's in: one 64pt tile per person, dashed tiles for spots still open.
struct PlayerTiles: View {
    let hit: Hit
    let me: UUID?
    @Environment(\.navigate) private var navigate

    var body: some View {
        let cards = hit.everyone
        let openCount = hit.isLive ? max(0, hit.spotsOpen) : 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(4, max(1, cards.count + openCount)))
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(cards) { card in
                // Everyone but you opens their profile, so a member can see, add or report anyone in the hit.
                Button { navigate(.player(card.id, hitID: hit.id)) } label: {
                    VStack(spacing: 4) {
                        PlayerAvatar(card: card, size: 28)
                        Text(card.id == me ? "You" : card.firstName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CourtlyColor.ink)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CourtlyColor.groupedBackground))
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(card.id == me)
                .accessibilityLabel(card.id == me ? "You" : "\(card.displayName), open profile")
            }
            ForEach(0..<openCount, id: \.self) { _ in
                VStack(spacing: 4) {
                    Circle()
                        .strokeBorder(CourtlyColor.placeholder, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 28, height: 28)
                    Text("Open")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CourtlyColor.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CourtlyColor.placeholder, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                )
            }
        }
    }
}
