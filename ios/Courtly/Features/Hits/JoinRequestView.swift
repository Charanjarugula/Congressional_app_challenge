import SwiftUI

/// Someone asked to join your hit: the hit, who they are, Accept or Decline.
struct JoinRequestView: View {
    let requestID: UUID

    @Environment(HitsStore.self) private var hits
    @Environment(\.navigate) private var navigate
    @State private var working: Bool?
    @State private var didLoad = false
    @State private var errorMessage: String?

    private var item: NeedsReplyItem? { hits.needsReplyItem(requestID: requestID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let item, let player = item.player {
                    hitCard(item.hit)
                    SectionHeader(title: "Wants to join", top: 24)
                    Card {
                        Button {
                            navigate(.player(player.id))
                        } label: {
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
                                Spacer(minLength: 8)
                                ChevronMark()
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 8) {
                        ActionButton(title: "Decline", style: .grouped, isLoading: working == false) { respond(accept: false) }
                        ActionButton(title: "Accept", isLoading: working == true) { respond(accept: true) }
                    }
                    .disabled(working != nil)   // one answer at a time
                    .padding(.top, 16)
                } else if hits.isLoadingFeed || !didLoad {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let error = hits.feedError {
                    QuietCard(title: "Couldn’t load this request", detail: error)
                    ActionButton(title: "Try again", style: .grouped) { Task { await hits.loadFeed() } }
                        .padding(.top, 12)
                } else {
                    QuietCard(title: "This request was already answered", detail: "Nothing left to do here.")
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .plainBackButton()
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: requestID) {
            // From a push or a stale snapshot the request may not be in the cached feed yet.
            if item == nil { await hits.loadFeed() }
            didLoad = true
        }
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
