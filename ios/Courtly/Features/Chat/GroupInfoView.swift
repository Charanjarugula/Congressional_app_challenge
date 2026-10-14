import SwiftUI

/// A group chat's members, with add, mute and leave.
struct GroupInfoView: View {
    let chatID: UUID

    @Environment(AppSession.self) private var session
    @Environment(InboxStore.self) private var inbox
    @Environment(\.navigate) private var navigate
    @State private var chat: Chat?
    @State private var loadFailed = false
    @State private var isMuted = false
    @State private var showsAddMembers = false
    @State private var showsLeaveAlert = false
    @State private var isLeaving = false
    @State private var errorMessage: String?

    private var me: UUID? { session.profile?.id }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let chat {
                    VStack(spacing: 8) {
                        ChatAvatar(chat: chat, me: me, size: 96)
                        Text(chat.title)
                            .font(.system(size: 28, weight: .bold))
                            .tracking(-0.6)
                            .foregroundStyle(CourtlyColor.ink)
                            .multilineTextAlignment(.center)
                        Text(chat.subtitle(me: me))
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    SectionHeader(title: "Members", actionTitle: "Add", action: { showsAddMembers = true }, top: 24)
                    CardRows(items: chat.members ?? []) { member in
                        memberRow(member)
                    }

                    SectionHeader(title: "Settings", top: 24)
                    Card {
                        VStack(spacing: 0) {
                            HStack {
                                Text("Mute notifications")
                                    .font(CourtlyFont.body)
                                    .foregroundStyle(CourtlyColor.ink)
                                Spacer()
                                Toggle("Mute", isOn: Binding(get: { isMuted }, set: { setMuted($0) }))
                                    .labelsHidden()
                                    .tint(CourtlyColor.blue)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 50)
                            HairlineSeparator()
                            SettingsRow(title: isLeaving ? "Leaving…" : "Leave group", titleColor: CourtlyColor.red, showsChevron: false) {
                                showsLeaveAlert = true
                            }
                        }
                    }
                } else if loadFailed {
                    QuietCard(title: "This group isn’t available", detail: "You may have left it.")
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .navigationTitle("Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: chatID) { await load() }
        .alert("Leave this group?", isPresented: $showsLeaveAlert) {
            Button("Leave", role: .destructive) { leave() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("You’ll stop getting its messages and hit requests.")
        }
        .sheet(isPresented: $showsAddMembers) {
            if let chat {
                AddMembersSheet(chat: chat) { updated in
                    self.chat = updated
                    Task { await inbox.load() }
                }
            }
        }
        .errorAlert($errorMessage)
    }

    private func memberRow(_ member: PlayerCard) -> some View {
        Button {
            if member.id != me { navigate(.player(member.id)) }
        } label: {
            HStack(spacing: 14) {
                PlayerAvatar(card: member, size: 44)
                VStack(alignment: .leading, spacing: 1) {
                    Text(member.id == me ? "You" : member.displayName)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    if !member.levelAndArea.isEmpty {
                        Text(member.levelAndArea)
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                }
                Spacer(minLength: 8)
                if member.id != me { ChevronMark() }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(member.id == me)
    }

    // MARK: - Data

    private func load() async {
        do {
            let page = try await API.Chats.page(chatID: chatID, limit: 1)
            chat = page.chat
            isMuted = page.chat.muted ?? false
            loadFailed = false
        } catch {
            if chat == nil { loadFailed = true }
        }
    }

    private func setMuted(_ muted: Bool) {
        isMuted = muted
        Task { @MainActor in
            do {
                try await API.Chats.setMuted(chatID, muted: muted)
            } catch {
                isMuted = !muted
                errorMessage = error.localizedDescription
            }
        }
    }

    private func leave() {
        isLeaving = true
        Task { @MainActor in
            do {
                try await API.Chats.leave(chatID)
                await inbox.load()
                navigate.pop()
                navigate.pop()
            } catch {
                errorMessage = error.localizedDescription
            }
            isLeaving = false
        }
    }
}

/// Friends who aren't in the group yet.
private struct AddMembersSheet: View {
    let chat: Chat
    let onAdded: (Chat) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friend] = []
    @State private var selected: Set<UUID> = []
    @State private var isLoading = true
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Add members", saveTitle: selected.isEmpty ? "Add" : "Add \(selected.count)", canSave: !selected.isEmpty, isSaving: isAdding, onSave: add) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if friends.isEmpty {
                QuietCard(title: "Everyone’s already here", detail: "All your friends are in this group.")
            } else {
                CardRows(items: friends) { friend in
                    Button {
                        if selected.contains(friend.id) { selected.remove(friend.id) } else { selected.insert(friend.id) }
                    } label: {
                        HStack(spacing: 14) {
                            PlayerAvatar(card: friend.card, size: 44)
                            Text(friend.card.displayName)
                                .font(CourtlyFont.bodySemibold)
                                .foregroundStyle(CourtlyColor.ink)
                            Spacer(minLength: 8)
                            SelectionMark(isSelected: selected.contains(friend.id))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task {
            let memberIDs = Set((chat.members ?? []).map(\.id))
            friends = ((try? await API.People.friends()) ?? []).filter { !memberIDs.contains($0.id) }
            isLoading = false
        }
        .errorAlert($errorMessage, title: "Couldn’t add them")
    }

    private func add() {
        isAdding = true
        Task { @MainActor in
            do {
                let updated = try await API.Chats.addMembers(chatID: chat.id, memberIDs: Array(selected))
                onAdded(updated)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isAdding = false
        }
    }
}
