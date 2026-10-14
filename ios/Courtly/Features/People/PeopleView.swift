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
                header
                searchField
                content
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await inbox.load() }
        .task(id: isActive) {
            guard isActive else { return }
            await inbox.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                guard !Task.isCancelled else { break }
                await inbox.load()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("People")
                .font(CourtlyFont.largeTitle)
                .tracking(-0.8)
                .foregroundStyle(CourtlyColor.ink)
            Spacer()
            Menu {
                Button("Add friends", systemImage: "person.badge.plus") { navigate(.addFriends) }
                Button("New group chat", systemImage: "person.3") { navigate(.newGroup) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(CourtlyColor.blue)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: CourtlyColor.ink.opacity(0.08), radius: 4, y: 2)
                    )
            }
            .accessibilityLabel("Add friends or start a group")
            if let card = session.profile?.card {
                PlayerAvatar(card: card, size: 40)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
            }
        }
        .frame(height: 52)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CourtlyColor.secondary)
            TextField("Search", text: $query)
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
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CourtlyColor.separator))
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let all = inbox.chats {
            let shown = filtered(all)
            if all.isEmpty {
                emptyState
            } else if shown.isEmpty {
                QuietCard(title: "No matches", detail: "Search looks through chat names.")
            } else {
                CardRows(items: shown) { chat in
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
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CourtlyColor.blue))
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

/// Avatar, name and time, last message, unread dot.
struct ChatRow: View {
    let chat: Chat
    let me: UUID?

    private static let hitPrefix = "Hit request: "

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
                HStack(spacing: 6) {
                    if isHitRequest {
                        Text("HIT")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CourtlyColor.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(CourtlyColor.blueTint))
                    }
                    Text(previewText)
                        .font(isCallToAction ? CourtlyFont.secondarySemibold : CourtlyFont.secondary)
                        .foregroundStyle(isCallToAction ? CourtlyColor.blue : CourtlyColor.secondary)
                        .lineLimit(1)
                }
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

    private var isHitRequest: Bool {
        chat.preview?.hasPrefix(Self.hitPrefix) == true
    }

    private var isCallToAction: Bool {
        chat.unreadCount > 0 && (chat.preview?.contains("added you back") == true)
    }

    private var previewText: String {
        guard let preview = chat.preview, !preview.isEmpty else { return "Say hi" }
        if isHitRequest { return String(preview.dropFirst(Self.hitPrefix.count)) }
        return preview
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
