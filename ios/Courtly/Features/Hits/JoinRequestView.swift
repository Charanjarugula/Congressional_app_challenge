import SwiftUI

/// Someone asked to join your hit: the hit, who they are, Accept or Decline.
struct JoinRequestView: View {
    let requestID: UUID

    @Environment(HitsStore.self) private var hits
    @Environment(\.navigate) private var navigate
    @State private var working: Bool?
    @State private var errorMessage: String?

    private var item: NeedsReplyItem? { hits.needsReplyItem(requestID: requestID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let item, let player = item.player {
                    hitCard(item.hit)
                    SectionHeader(title: "Wants to join", top: 24)
                    Card {
                        HStack(spacing: 14) {
                            PlayerAvatar(card: player, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(player.displayName)
                                    .font(.system(size: 20, weight: .bold))
                                    .tracking(-0.3)
                                    .foregroundStyle(CourtlyColor.ink)
                                if !player.levelAndArea.isEmpty {
                                    Text(player.levelAndArea)
                                        .font(CourtlyFont.secondary)
                                        .foregroundStyle(CourtlyColor.secondary)
                                }
                                Text(player.hitsPlayed == 1 ? "1 hit played" : "\(player.hitsPlayed) hits played")
                                    .font(CourtlyFont.caption)
                                    .foregroundStyle(CourtlyColor.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                    }
                    HStack(spacing: 8) {
                        ActionButton(title: "Decline", style: .grouped, isLoading: working == false) { respond(accept: false) }
                        ActionButton(title: "Accept", isLoading: working == true) { respond(accept: true) }
                    }
                    .padding(.top, 16)
                } else {
                    QuietCard(title: "This request was already answered", detail: "Nothing left to do here.")
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .errorAlert($errorMessage)
    }

    private func hitCard(_ hit: Hit) -> some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(hit.timeLabel)
                        .font(CourtlyFont.rounded(28))
                        .tracking(-0.5)
                        .foregroundStyle(CourtlyColor.ink)
                    Spacer()
                    StatusPill(kind: hit.statusKind)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.formatLine)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    Text(hit.courtLine)
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(CourtlyColor.secondary)
                }
            }
        }
    }

    private func respond(accept: Bool) {
        working = accept
        Task { @MainActor in
            do {
                let hit = try await hits.respond(requestID: requestID, accept: accept)
                if accept {
                    navigate.replaceTop(.hit(hit.id))
                } else {
                    navigate.pop()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            working = nil
        }
    }
}
