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
                .font(CourtlyFont.sheetTitle)
                .tracking(-0.4)
                .foregroundStyle(CourtlyColor.ink)
            Text("Pick one of your hits with an open spot.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    if openHits.isEmpty {
                        QuietCard(title: "No open hits", detail: "Plan a hit from Play, then invite \(player.firstName) from here.")
                    } else {
                        CardRows(items: openHits) { hit in
                            HStack(spacing: 14) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(hit.dayText)
                                    Text(hit.clockText)
                                }
                                .font(CourtlyFont.rounded(17))
                                .foregroundStyle(CourtlyColor.ink)
                                .frame(width: 76, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(hit.format.shortTitle) · \(hit.spotsLabel)")
                                        .font(CourtlyFont.bodySemibold)
                                        .foregroundStyle(CourtlyColor.ink)
                                    Text(hit.court.shortName)
                                        .font(CourtlyFont.caption)
                                        .foregroundStyle(CourtlyColor.secondary)
                                }
                                Spacer(minLength: 8)
                                PillButton(
                                    title: sent.contains(hit.id) ? "Sent" : (sending == hit.id ? "Sending…" : "Send"),
                                    style: sent.contains(hit.id) ? .tint : .filled,
                                    showsCheck: sent.contains(hit.id)
                                ) {
                                    send(hit)
                                }
                                .disabled(sent.contains(hit.id) || sending != nil)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.top, 16)
            }
            TextActionButton(title: "Done") { dismiss() }
        }
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .presentationDetents([.medium, .large])
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
