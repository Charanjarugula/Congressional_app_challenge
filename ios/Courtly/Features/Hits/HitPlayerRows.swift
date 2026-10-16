import SwiftUI

/// Participants stay attached to their profile action; open spaces are informational.
struct HitPlayerRows: View {
    let hit: Hit
    let me: UUID?
    @Environment(\.navigate) private var navigate

    var body: some View {
        Card(radius: 22) {
            VStack(spacing: 0) {
                ForEach(Array(hit.everyone.enumerated()), id: \.element.id) { index, card in
                    if index > 0 { HairlineSeparator() }
                    Button { navigate(.player(card.id, hitID: hit.id)) } label: {
                        HStack(spacing: 10) {
                            PlayerAvatar(card: card, size: 44)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.displayName).font(.body.weight(.semibold)).foregroundStyle(CourtlyColor.ink)
                                Text([card.id == me ? "You" : nil, card.id == hit.host.id ? "Host" : nil, card.level?.title].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(CourtlyColor.secondary)
                            }
                            Spacer(minLength: 8)
                            if card.id != me { ChevronMark() }
                        }
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(card.id == me)
                }
                if hit.isLive && hit.spotsOpen > 0 {
                    HairlineSeparator()
                    HStack(spacing: 10) {
                        Image("CourtsideBall").renderingMode(.template)
                            .foregroundStyle(CourtlyColor.blue)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(CourtlyColor.blueTint))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(hit.spotsOpen == 1 ? "Open spot" : "\(hit.spotsOpen) open spots")
                                .font(.body.weight(.semibold)).foregroundStyle(CourtlyColor.ink)
                            Text(hit.viewer.isHost ? "Invite a friend to fill it" : "Join \(hit.host.firstName) on court")
                                .font(.caption).foregroundStyle(CourtlyColor.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                }
            }
        }
    }
}
