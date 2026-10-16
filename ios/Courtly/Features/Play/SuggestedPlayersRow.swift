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
    @State private var pendingRequest: PendingFriendRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Players you might know")
                .font(.headline)
                .foregroundStyle(CourtlyColor.ink)
            Card(radius: 22) {
                VStack(spacing: 0) {
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        if index > 0 { HairlineSeparator() }
                        card(player)
                    }
                }
            }
            PrimaryButton(title: "Add friends", style: .lime, compact: true, action: onSeeAll)
        }
        .takeBackRequestDialog($pendingRequest) { toggle($0) }
        .errorAlert($errorMessage, title: "Couldn’t send the request")
    }

    private func card(_ player: SuggestedPlayer) -> some View {
        let isRequested = requested.contains(player.id)
        return HStack(spacing: 10) {
            Button { navigate(.player(player.id)) } label: {
                HStack(spacing: 10) {
                    PlayerAvatar(card: player.card, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.card.displayName)
                            .font(.headline)
                            .foregroundStyle(CourtlyColor.ink)
                        Text(player.mutualFriends.mutualLabel ?? player.reason ?? player.card.levelAndArea)
                            .font(.footnote)
                            .foregroundStyle(CourtlyColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                if isRequested {
                    pendingRequest = PendingFriendRequest(id: player.id, firstName: player.card.firstName)
                } else {
                    toggle(player.id)
                }
            } label: {
                Group {
                    if busy.contains(player.id) { ProgressView() }
                    else { Text(isRequested ? "Requested" : "Add").font(.footnote.weight(.semibold)) }
                }
                .foregroundStyle(CourtlyColor.blue)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(busy.contains(player.id))
            .accessibilityLabel("\(isRequested ? "Cancel request to" : "Add") \(player.card.displayName)")
        }
        .padding(14)
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
