import SwiftUI

/// "Suggested for you": a sideways row of players near you, each with Add, the way Instagram fills an
/// empty feed. Tapping a card opens the profile; Add sends a friend request and turns into Requested.
struct SuggestedPlayersRow: View {
    let players: [SuggestedPlayer]
    @Binding var requested: Set<UUID>
    var onSeeAll: () -> Void

    @Environment(\.navigate) private var navigate
    @State private var busy: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Suggested for you")
                    .font(CourtlyFont.sectionHeader)
                    .foregroundStyle(CourtlyColor.ink)
                Spacer()
                Button("See all", action: onSeeAll)
                    .font(CourtlyFont.captionSemibold)
                    .foregroundStyle(CourtlyColor.blue)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(players) { player in
                        card(player)
                    }
                }
                .padding(.horizontal, CourtlyMetrics.screenPadding)
            }
            .padding(.horizontal, -CourtlyMetrics.screenPadding)   // cards run to the screen edges
        }
        .errorAlert($errorMessage, title: "Couldn’t send the request")
    }

    private func card(_ player: SuggestedPlayer) -> some View {
        let isRequested = requested.contains(player.id)
        return VStack(spacing: 8) {
            Button { navigate(.player(player.id)) } label: {
                VStack(spacing: 6) {
                    PlayerAvatar(card: player.card, size: 64)
                    Text(player.card.displayName)
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                        .lineLimit(1)
                    Text(player.mutualFriends.mutualLabel ?? player.reason ?? player.card.levelAndArea)
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2, reservesSpace: true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { toggle(player.id) } label: {
                Text(isRequested ? "Requested" : "Add")
                    .font(CourtlyFont.captionSemibold)
                    .foregroundStyle(isRequested ? CourtlyColor.ink : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isRequested ? CourtlyColor.groupedBackground : CourtlyColor.blue)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(12)
        .frame(width: 148)
        .background(RoundedRectangle(cornerRadius: CourtlyMetrics.cardRadius, style: .continuous).fill(CourtlyColor.card))
    }

    private func toggle(_ id: UUID) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        let wasRequested = requested.contains(id)
        if wasRequested { requested.remove(id) } else { requested.insert(id) }
        Task { @MainActor in
            defer { busy.remove(id) }
            do {
                if wasRequested {
                    _ = try await API.People.cancelFriendRequest(id)
                } else {
                    _ = try await API.People.addFriend(id)
                }
            } catch {
                if wasRequested { requested.insert(id) } else { requested.remove(id) }
                errorMessage = error.localizedDescription
            }
        }
    }
}
