import SwiftUI

/// One chat list: DMs, groups and hit chats, newest activity first.
struct PeopleView: View {
    @Environment(InboxStore.self) private var inbox
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    let isActive: Bool

    @State private var query = ""

    private var me: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchField
                content
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .navigationTitle("People")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await inbox.load() }
        .task(id: isActive) {
            guard isActive else { return }
            await inbox.load()
            // Realtime (in the tab shell) refreshes on new messages; this is the fallback.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await inbox.load()
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CourtlyColor.secondary)
            TextField("Search chat names", text: $query)
                .font(CourtlyFont.body)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(CourtlyColor.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CourtlyColor.card))
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let error = inbox.requestsError {
            QuietCard(title: "Couldn’t load friend requests", detail: error)
                .padding(.bottom, 12)
        }
        if query.isEmpty, let requests = inbox.requests, !requests.incoming.isEmpty {
            requestsRow(requests.incoming)
                .padding(.bottom, 12)
        }
        if let all = inbox.chats {
            let shown = filtered(all)
            if all.isEmpty {
                emptyState
            } else if shown.isEmpty {
                QuietCard(title: "No matches", detail: "Search looks through chat names.")
            } else {
                SectionHeader(title: "Chats")
                CardRows(items: shown, radius: 22) { chat in
                    Button {
                        inbox.markRead(chat.id)
                        navigate(.chat(chat.id))
                    } label: {
                        ChatRow(chat: chat, me: me)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if let error = inbox.lastError, !inbox.isLoading {
            QuietCard(title: "Couldn’t load chats", detail: error)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        }
    }

    /// One row above the chats while someone is waiting on you, like a message-requests folder.
    private func requestsRow(_ incoming: [FriendRequest]) -> some View {
        Button {
            navigate(.friendRequests)
        } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    if incoming.count >= 2 {
                        PlayerAvatar(card: incoming[1].card, size: 36)
                            .frame(width: 52, height: 52, alignment: .topLeading)
                        PlayerAvatar(card: incoming[0].card, size: 36)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    } else if let first = incoming.first {
                        PlayerAvatar(card: first.card, size: 52)
                    }
                }
                .frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Friend requests")
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    Text(requestsPreview(incoming))
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.blue)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                CountBadge(count: incoming.count)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CourtlyColor.placeholder)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(CourtlyColor.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func requestsPreview(_ incoming: [FriendRequest]) -> String {
        let names = incoming.prefix(2).map(\.card.firstName)
        switch incoming.count {
        case 1: return "\(names[0]) wants to be friends"
        case 2: return "\(names[0]) and \(names[1]) want to be friends"
        default: return "\(names[0]), \(names[1]) and \(incoming.count - 2) more"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No chats yet")
                .font(.system(size: 20, weight: .bold))
                .tracking(-0.3)
                .foregroundStyle(CourtlyColor.ink)
            Text("Add a friend and the chat opens here. Hits you join get a chat too.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
            Button {
                navigate(.addFriends)
            } label: {
                Text("Add friends")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CourtlyColor.blue))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 64)
    }

    private func filtered(_ chats: [Chat]) -> [Chat] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return chats }
        return chats.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }
}

/// Avatar, name and time, the newest message, unread dot.
struct ChatRow: View {
    let chat: Chat
    let me: UUID?

    var body: some View {
        HStack(spacing: 14) {
            ChatAvatar(chat: chat, me: me, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(chat.title)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let at = chat.lastMessageAt {
                        Text(HitFormatting.inboxTime(at))
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                }
                Text(chat.preview?.isEmpty == false ? chat.preview! : "Say hi")
                    .font(chat.unreadCount > 0 ? CourtlyFont.secondarySemibold : CourtlyFont.secondary)
                    .foregroundStyle(chat.unreadCount > 0 ? CourtlyColor.ink : CourtlyColor.secondary)
                    .lineLimit(1)
            }
            if chat.unreadCount > 0 {
                Circle()
                    .fill(CourtlyColor.blue)
                    .frame(width: 10, height: 10)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

/// One photo for a DM, two overlapping for groups and hit chats.
struct ChatAvatar: View {
    let chat: Chat
    let me: UUID?
    var size: CGFloat = 52

    var body: some View {
        let others = chat.others(than: me)
        ZStack(alignment: .bottomTrailing) {
            if chat.type != .dm && others.count >= 2 {
                PlayerAvatar(card: others[0], size: size * 0.69)
                    .frame(width: size, height: size, alignment: .topLeading)
                PlayerAvatar(card: others[1], size: size * 0.69)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            } else if let other = others.first {
                PlayerAvatar(card: other, size: size)
            } else {
                InitialsAvatar(initials: String(chat.title.prefix(2)).uppercased(), size: size, style: .muted)
            }
        }
        .frame(width: size, height: size)
    }
}
