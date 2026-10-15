import SwiftUI

/// A text bubble, a system line, or a hit request card.
struct MessageRow: View {
    let message: Message
    let isMine: Bool
    let showsAvatar: Bool
    /// First of a run from the same sender: the name goes above it in group and hit chats.
    var startsRun = true
    var onOpenSender: (UUID) -> Void = { _ in }
    var onReport: () -> Void = {}

    var body: some View {
        switch message.type {
        case .system:
            Text(message.body)
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case .hitInvite:
            HStack {
                if isMine { Spacer(minLength: 40) }
                if let invite = message.invite {
                    HitInviteCard(invite: invite)
                } else {
                    bubble
                }
                if !isMine { Spacer(minLength: 40) }
            }
        case .text:
            HStack(alignment: .bottom, spacing: 8) {
                if isMine {
                    Spacer(minLength: 60)
                } else if showsAvatar, let sender = message.sender {
                    Button { onOpenSender(sender.id) } label: { PlayerAvatar(card: sender, size: 28) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(sender.displayName), open profile")
                }
                if !isMine && showsAvatar && startsRun, let sender = message.sender {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sender.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CourtlyColor.secondary)
                            .padding(.leading, 4)
                        bubble
                    }
                } else {
                    bubble
                }
                if !isMine { Spacer(minLength: 60) }
            }
        }
    }

    private var bubble: some View {
        textBubble
            .contextMenu {
                if !isMine && message.type == .text && message.sender != nil {
                    Button("Report", systemImage: "exclamationmark.bubble") { onReport() }
                }
            }
    }

    private var textBubble: some View {
        Text(message.body)
            .font(CourtlyFont.body)
            .foregroundStyle(isMine ? .white : CourtlyColor.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isMine ? CourtlyColor.blue : CourtlyColor.groupedBackground)
            )
            .frame(maxWidth: 260, alignment: isMine ? .trailing : .leading)
    }
}
