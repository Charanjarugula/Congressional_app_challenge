import SwiftUI

/// A hit request inside a chat: the hit, who's in, how long is left, and "I’m in".
struct HitInviteCard: View {
    let invite: HitInvite

    @Environment(HitsStore.self) private var hits
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    /// The hit as returned by the player's own claim, until the next refresh brings the server's copy.
    @State private var claimed: Hit?
    @State private var isClaiming = false
    @State private var errorMessage: String?

    private var me: UUID? { session.profile?.id }
    private var hit: Hit { claimed ?? invite.hit }

    var body: some View {
        card.onChange(of: invite) { _, _ in claimed = nil }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Hit request")
                    .font(CourtlyFont.captionSemibold)
                    .foregroundStyle(CourtlyColor.blue)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .bold))
                    Text(HitFormatting.timeLeft(until: invite.expiresAt))
                }
                .font(CourtlyFont.captionSemibold)
                .foregroundStyle(CourtlyColor.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Button {
                navigate(.hit(hit.id))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hit.timeLabel)
                        .font(CourtlyFont.rounded(24))
                        .tracking(-0.3)
                        .foregroundStyle(CourtlyColor.ink)
                    Text("\(hit.format.title) · \(hit.court.name)")
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(CourtlyColor.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 14)

            PlayerTiles(hit: hit, me: me)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)

            action
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: 330)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CourtlyColor.separator, lineWidth: 1))
        .errorAlert($errorMessage)
    }

    @ViewBuilder
    private var action: some View {
        if hit.isMember {
            ActionButton(title: hit.viewer.isHost ? "Your hit" : "You’re in", style: .grouped, isEnabled: false) {}
        } else if !hit.isLive {
            ActionButton(title: "Closed", style: .grouped, isEnabled: false) {}
        } else if hit.isFull || invite.status == .filled {
            ActionButton(title: "Filled", style: .grouped, isEnabled: false) {}
        } else if !invite.isOpen {
            ActionButton(title: "Closed", style: .grouped, isEnabled: false) {}
        } else {
            ActionButton(title: "I’m in", style: .lime, isLoading: isClaiming) { claim() }
        }
    }

    private func claim() {
        isClaiming = true
        Task { @MainActor in
            do {
                claimed = try await hits.claimInvite(invite.id)
            } catch {
                errorMessage = error.localizedDescription
            }
            isClaiming = false
        }
    }
}
