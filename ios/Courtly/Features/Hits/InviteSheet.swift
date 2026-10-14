import SwiftUI

/// Offer a hit's open spots to friends or a group chat. The first to accept takes the spot.
struct InviteSheet: View {
    let hit: Hit

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var groups: [Chat] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var sent: Set<UUID> = []
    @State private var sending: UUID?
    @State private var errorMessage: String?

    private var me: UUID? { session.profile?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .padding(.bottom, 18)
            Text("Invite")
                .font(CourtlyFont.sheetTitle)
                .tracking(-0.4)
                .foregroundStyle(CourtlyColor.ink)
            Text("Friends or a group chat. First to accept takes the spot.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: 0) {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if loadFailed {
                        VStack(spacing: 12) {
                            QuietCard(title: "Couldn’t load your friends", detail: "Check your connection and try again.")
                            Button("Try again") { Task { await load() } }
                                .font(CourtlyFont.secondarySemibold)
                                .foregroundStyle(CourtlyColor.blue)
                        }
                    } else if groups.isEmpty && friends.isEmpty {
                        QuietCard(title: "No one to invite yet", detail: "Add friends from People and they’ll show up here.")
                    } else {
                        Card {
                            VStack(spacing: 0) {
                                ForEach(groups) { group in
                                    groupRow(group)
                                    HairlineSeparator()
                                }
                                ForEach(Array(friends.enumerated()), id: \.element.id) { index, friend in
                                    if index > 0 { HairlineSeparator() }
                                    friendRow(friend)
                                }
                            }
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
        .task { await load() }
        .errorAlert($errorMessage, title: "Couldn’t send the invite")
    }

    // MARK: - Rows

    private func groupRow(_ group: Chat) -> some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                let members = group.others(than: me)
                if members.count >= 2 {
                    PlayerAvatar(card: members[0], size: 30)
                        .frame(width: 44, height: 44, alignment: .topLeading)
                    PlayerAvatar(card: members[1], size: 30)
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                } else {
                    InitialsAvatar(initials: String(group.title.prefix(2)).uppercased(), size: 44, style: .muted)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .lineLimit(1)
                Text(group.subtitle(me: me))
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
            }
            Spacer(minLength: 8)
            sendButton(chatID: group.id, targetUserID: nil)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func friendRow(_ friend: Friend) -> some View {
        HStack(spacing: 14) {
            PlayerAvatar(card: friend.card, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(friend.card.displayName)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .lineLimit(1)
                Text(friendDetail(friend.card))
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if let chatID = friend.dmChatId {
                sendButton(chatID: chatID, targetUserID: friend.card.id)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    private func sendButton(chatID: UUID, targetUserID: UUID?) -> some View {
        PillButton(
            title: sent.contains(chatID) ? "Sent" : (sending == chatID ? "Sending…" : "Send"),
            style: sent.contains(chatID) ? .tint : .filled,
            showsCheck: sent.contains(chatID)
        ) {
            send(chatID: chatID, targetUserID: targetUserID)
        }
        .disabled(sent.contains(chatID) || sending != nil)
    }

    /// "Free Sunday" when the hit lands in a block they marked free, otherwise their level.
    private func friendDetail(_ card: PlayerCard) -> String {
        if let mask = card.availabilityMask, let bit = Self.availabilityBit(for: hit.startsAt), mask & (1 << Int32(bit)) != 0 {
            let weekday = Calendar.current.component(.weekday, from: hit.startsAt)
            return "Free \(Calendar.current.weekdaySymbols[weekday - 1])"
        }
        return card.levelAndArea.isEmpty ? "Friend" : card.levelAndArea
    }

    /// Bit index for the block a time falls in: Monday = 0; morning 7–11, afternoon 12–4, evening 5–9.
    private static func availabilityBit(for date: Date) -> Int? {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let day = (calendar.component(.weekday, from: date) + 5) % 7
        let block: Int
        switch hour {
        case 7..<11: block = 0
        case 12..<16: block = 1
        case 17..<21: block = 2
        default: return nil
        }
        return day * 3 + block
    }

    // MARK: - Data

    /// A failed load says so instead of looking like a player with no one to invite.
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let friendList = API.People.friends()
        async let inbox = API.Chats.inbox()
        do {
            friends = try await friendList
            groups = try await inbox.filter { $0.type == .group }
            loadFailed = false
        } catch {
            loadFailed = true
        }
    }

    private func send(chatID: UUID, targetUserID: UUID?) {
        sending = chatID
        Task { @MainActor in
            do {
                _ = try await API.Hits.sendInvite(hitID: hit.id, chatID: chatID, targetUserID: targetUserID)
                sent.insert(chatID)
            } catch {
                errorMessage = error.localizedDescription
            }
            sending = nil
        }
    }
}
