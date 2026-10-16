import SwiftUI

/// Pick one of your open hits to invite this player to.
struct InviteToHitSheet: View {
    let player: PlayerCard
    let dmChatID: UUID?

    @Environment(HitsStore.self) private var hits
    @Environment(\.dismiss) private var dismiss
    @State private var sent: Set<UUID> = []
    @State private var sending: UUID?
    @State private var errorMessage: String?

    private var openHits: [Hit] {
        (hits.myHits?.upcoming ?? []).filter { $0.viewer.isHost && $0.isLive && $0.spotsOpen > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 18)
            Text("Invite \(player.firstName)")
                .font(.largeTitle.bold())
                .tracking(-0.4)
                .foregroundStyle(CourtlyColor.ink)
            Text("Pick one of your hits with an open spot.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    if openHits.isEmpty {
                        QuietCard(title: "No open hits", detail: "Plan a hit from Explore, then invite \(player.firstName) from here.")
                    } else {
                        VStack(spacing: 16) {
                            ForEach(openHits) { hit in
                                VStack(spacing: 12) {
                                    Card(padding: 18, radius: 22) { HitSummary(hit: hit, showsHost: false) }
                                    ActionButton(title: sent.contains(hit.id) ? "Sent" : "Send",
                                                 style: sent.contains(hit.id) ? .quiet : .lime,
                                                 height: 48, radius: 16,
                                                 isEnabled: !sent.contains(hit.id) && sending == nil,
                                                 isLoading: sending == hit.id) { send(hit) }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 16)
            }
            PrimaryButton(title: "Done", style: .lime, compact: true) { dismiss() }
                .padding(.vertical, 16)
        }
        .padding(.horizontal, 24)
        .background(CourtlyColor.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .errorAlert($errorMessage, title: "Couldn’t send the invite")
    }

    private func send(_ hit: Hit) {
        guard let dmChatID else {
            errorMessage = "Add \(player.firstName) as a friend first."
            return
        }
        sending = hit.id
        Task { @MainActor in
            do {
                _ = try await API.Hits.sendInvite(hitID: hit.id, chatID: dmChatID, targetUserID: player.id)
                sent.insert(hit.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = nil
        }
    }
}
