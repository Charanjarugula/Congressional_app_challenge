import SwiftUI

/// A player's photo, falling back to their initials while it loads or when they have none.
struct PlayerAvatar: View {
    let card: PlayerCard
    var size: CGFloat = 44
    var style: InitialsAvatar.Style = .tint

    var body: some View {
        if let url = card.photoURL {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    InitialsAvatar(initials: card.initials, size: size, style: style)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            InitialsAvatar(initials: card.initials, size: size, style: style)
        }
    }
}

/// Up to three overlapping avatars.
struct AvatarStack: View {
    let cards: [PlayerCard]
    var size: CGFloat = 32

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(cards.prefix(3)) { card in
                PlayerAvatar(card: card, size: size)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
    }
}

extension PlayerCard {
    var photoURL: URL? {
        photoPath.map { SupabaseClient.shared.publicURL(bucket: "avatars", path: $0) }
    }
}
