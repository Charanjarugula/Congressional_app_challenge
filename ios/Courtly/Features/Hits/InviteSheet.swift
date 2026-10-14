import SwiftUI

/// Offer a hit's open spots to friends or a group chat. The first to accept takes the spot.
struct InviteSheet: View {
    let hit: Hit

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var groups: [Chat] = []
    @State private var isLoading = true
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
            ChatAvatar(chat: group, me: me, size: 44)
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
        if let mask = card.availabilityMask, let slot = AvailabilityMask.slot(for: hit.startsAt),
           AvailabilityMask(rawValue: mask).contains(day: slot.day, block: slot.block) {
            let weekday = Calendar.current.component(.weekday, from: hit.startsAt)
            return "Free \(Calendar.current.weekdaySymbols[weekday - 1])"
        }
        return card.levelAndArea.isEmpty ? "Friend" : card.levelAndArea
    }

    // MARK: - Data

    private func load() async {
        defer { isLoading = false }
        async let friendList = API.People.friends()
        async let inbox = API.Chats.inbox()
        friends = (try? await friendList) ?? []
        groups = ((try? await inbox) ?? []).filter { $0.type == .group }
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
