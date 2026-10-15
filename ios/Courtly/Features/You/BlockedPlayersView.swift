import SwiftUI

/// Players you've blocked, with a way back.
struct BlockedPlayersView: View {
    @Environment(AppSession.self) private var session
    @State private var players: [PlayerCard]?
    @State private var unblocking: UUID?
    @State private var loadError: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let players {
                    if players.isEmpty {
                        QuietCard(title: "No blocked players", detail: "Players you block won’t see your hits or messages, and you won’t see theirs.")
                    } else {
                        CardRows(items: players) { card in
                            HStack(spacing: 14) {
                                PlayerAvatar(card: card, size: 44)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(card.displayName)
                                        .font(CourtlyFont.bodySemibold)
                                        .foregroundStyle(CourtlyColor.ink)
                                    if !card.levelAndArea.isEmpty {
                                        Text(card.levelAndArea)
                                            .font(CourtlyFont.caption)
                                            .foregroundStyle(CourtlyColor.secondary)
                                    }
                                }
                                Spacer(minLength: 8)
                                PillButton(title: unblocking == card.id ? "Unblocking…" : "Unblock", style: .tint) { unblock(card) }
                                    .disabled(unblocking != nil)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }
                    }
                } else if let loadError {
                    QuietCard(title: "Couldn’t load blocked players", detail: loadError)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .plainBackButton()
        .navigationTitle("Blocked players")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            do {
                players = try await API.People.blocked()
            } catch {
                loadError = error.localizedDescription
            }
        }
        .errorAlert($errorMessage)
    }

    private func unblock(_ card: PlayerCard) {
        unblocking = card.id
        Task { @MainActor in
            do {
                try await API.People.unblock(card.id)
                players?.removeAll { $0.id == card.id }
                await session.refreshProfile()
            } catch {
                errorMessage = error.localizedDescription
            }
            unblocking = nil
        }
    }
}
