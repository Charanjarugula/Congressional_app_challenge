import SwiftUI

/// A short list of players, each a row that opens their profile. Used for mutual friends and who's in a hit.
struct PlayersSheet: View {
    let title: String
    let players: [PlayerCard]
    let open: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 18)
            Text(title)
                .font(CourtlyFont.sheetTitle)
                .tracking(-0.4)
                .foregroundStyle(CourtlyColor.ink)
            ScrollView {
                CardRows(items: players, radius: 22) { player in
                    Button {
                        open(player.id)
                    } label: {
                        HStack(spacing: 14) {
                            PlayerAvatar(card: player, size: 44)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(player.displayName)
                                    .font(CourtlyFont.bodySemibold)
                                    .foregroundStyle(CourtlyColor.ink)
                                Text(player.levelAndArea)
                                    .font(CourtlyFont.caption)
                                    .foregroundStyle(CourtlyColor.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 16)
            }
            TextActionButton(title: "Done") { dismiss() }
        }
        .padding(.horizontal, 24)
        .background(CourtlyColor.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
    }
}
