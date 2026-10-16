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
    @State private var muteTask: Task<Void, Never>?
    @State private var muteSaves = 0
    @State private var showsAddMembers = false
    @State private var showsLeaveAlert = false
    @State private var isLeaving = false
    @State private var errorMessage: String?

    init(chatID: UUID) { self.chatID = chatID }

    #if DEBUG && targetEnvironment(simulator)
    init(preview: Chat) {
        chatID = preview.id
        _chat = State(initialValue: preview)
        _isMuted = State(initialValue: preview.muted ?? false)
    }
    #endif

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

                    if chat.leftAt == nil {
                        SectionHeader(title: "Members", actionTitle: "Add", action: { showsAddMembers = true }, top: 24)
                    } else {
                        SectionHeader(title: "Members", top: 24)
                    }
                    CardRows(items: chat.members ?? [], radius: 22) { member in
                        memberRow(member)
                    }

                    if chat.leftAt != nil {
                        Text("You left this group. You can still read it, but not add people or change settings.")
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .padding(.top, 16)
                            .padding(.horizontal, 4)
                    } else {
                    SectionHeader(title: "Settings", top: 24)
                    Card(radius: 22) {
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
                            .frame(minHeight: 50)
                            HairlineSeparator()
                            SettingsRow(title: isLeaving ? "Leaving…" : "Leave group", titleColor: CourtlyColor.red, showsChevron: false) {
                                showsLeaveAlert = true
                            }
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
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .plainBackButton()
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
            let fresh = try await API.Chats.get(chatID)
            chat = fresh
            isMuted = fresh.muted ?? false
            loadFailed = false
        } catch {
            if chat == nil { loadFailed = true }
        }
    }

    /// Flips reach the server one at a time, in order; a flip made while one is saving supersedes it,
    /// and a stale failure can't undo a newer choice.
    private func setMuted(_ muted: Bool) {
        isMuted = muted
        muteSaves += 1
        let save = muteSaves
        let previous = muteTask
        muteTask = Task { @MainActor in
            await previous?.value
            guard save == muteSaves else { return }
            do {
                try await API.Chats.setMuted(chatID, muted: muted)
            } catch {
                guard save == muteSaves else { return }
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
    @State private var loadFailed = false
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Add members", saveTitle: selected.isEmpty ? "Add" : "Add \(selected.count)", canSave: !selected.isEmpty, isSaving: isAdding, onSave: add) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if loadFailed {
                VStack(spacing: 12) {
                    QuietCard(title: "Couldn’t load your friends", detail: "Check your connection and try again.")
                    Button("Try again") { Task { await load() } }
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.blue)
                }
            } else if friends.isEmpty {
                QuietCard(title: "Everyone’s already here", detail: "All your friends are in this group.")
            } else {
                CardRows(items: friends, radius: 22) { friend in
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
        .task { await load() }
        .errorAlert($errorMessage, title: "Couldn’t add them")
    }

    /// A failed load says so instead of looking like a group that already has everyone.
    private func load() async {
        isLoading = true
        do {
            let memberIDs = Set((chat.members ?? []).map(\.id))
            friends = try await API.People.friends().filter { !memberIDs.contains($0.id) }
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
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
