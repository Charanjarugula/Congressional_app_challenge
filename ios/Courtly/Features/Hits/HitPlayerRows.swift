import SwiftUI

/// Host first, then players, then one row per open spot. Your own row is plain text (never a dimmed
/// button); an open spot is a dashed circle with a plus, which the host can tap to invite.
struct HitPlayerRows: View {
    let hit: Hit
    let me: UUID?
    var onInvite: (() -> Void)? = nil
    @Environment(\.navigate) private var navigate

    private static let shownSlots = 3

    var body: some View {
        Card(radius: 22) {
            VStack(spacing: 0) {
                ForEach(Array(hit.everyone.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { HairlineSeparator() }
                    if card.id == me {
                        playerRow(card, showsChevron: false)
                            .accessibilityElement(children: .combine)
                    } else {
                        Button { navigate(.player(card.id, hitID: hit.id)) } label: {
                            playerRow(card, showsChevron: true).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                if hit.isLive && hit.spotsOpen > 0 {
                    let shown = min(hit.spotsOpen, Self.shownSlots)
                    ForEach(0..<shown, id: \.self) { index in
                        HairlineSeparator()
                        let extra = index == shown - 1 ? hit.spotsOpen - shown : 0
                        if let onInvite {
                            Button(action: onInvite) { slotRow(extra: extra, showsChevron: true).contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Invite someone")
                        } else {
                            slotRow(extra: extra, showsChevron: false)
                                .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
    }

    private func playerRow(_ card: PlayerCard, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            PlayerAvatar(card: card, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.displayName).font(.body.weight(.semibold)).foregroundStyle(CourtlyColor.ink)
                Text([card.id == me ? "You" : nil, card.id == hit.host.id ? "Host" : nil, card.level?.title].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(CourtlyColor.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron { ChevronMark() }
        }
        .padding(14)
    }

    private func slotRow(extra: Int, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CourtlyColor.blue)
                .frame(width: 44, height: 44)
                .background(Circle().strokeBorder(CourtlyColor.blue.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(extra > 0 ? "\(extra + 1) open spots" : "Open spot")
                    .font(.body.weight(.semibold)).foregroundStyle(CourtlyColor.ink)
                Text(onInvite != nil ? "Invite someone" : hit.isMember ? "Waiting for a player" : "Could be you")
                    .font(.caption).foregroundStyle(CourtlyColor.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron { ChevronMark() }
        }
        .padding(14)
    }
}
