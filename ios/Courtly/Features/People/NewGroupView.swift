import SwiftUI

/// Name a group and pick friends. The chat opens as soon as it exists.
struct NewGroupView: View {
    @Environment(InboxStore.self) private var inbox
    @Environment(\.navigate) private var navigate
    @State private var name = ""
    @State private var friends: [Friend] = []
    @State private var selected: Set<UUID> = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selected.isEmpty && !isCreating
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel(title: "Name")
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                FieldBox(fill: .white, cornerRadius: 16) {
                    TextField("Wellington Weekend Crew", text: $name)
                        .font(CourtlyFont.body)
                }
                SectionLabel(title: selected.isEmpty ? "Friends" : "Friends · \(selected.count) picked")
                    .padding(.top, 18)
                    .padding(.bottom, 8)
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
                    VStack(spacing: 12) {
                        QuietCard(title: "No friends yet", detail: "Groups are made of friends. Add some first.")
                        Button("Add friends") { navigate(.addFriends) }
                            .font(CourtlyFont.secondarySemibold)
                            .foregroundStyle(CourtlyColor.blue)
                    }
                } else {
                    CardRows(items: friends, radius: 22) { friend in
                        Button {
                            if selected.contains(friend.id) { selected.remove(friend.id) } else { selected.insert(friend.id) }
                        } label: {
                            HStack(spacing: 14) {
                                PlayerAvatar(card: friend.card, size: 44)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(friend.card.displayName)
                                        .font(CourtlyFont.bodySemibold)
                                        .foregroundStyle(CourtlyColor.ink)
                                    if !friend.card.levelAndArea.isEmpty {
                                        Text(friend.card.levelAndArea)
                                            .font(CourtlyFont.caption)
                                            .foregroundStyle(CourtlyColor.secondary)
                                    }
                                }
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
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .plainBackButton()
        .navigationTitle("New group")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Create group", style: .lime, compact: true, isEnabled: canCreate, isLoading: isCreating, action: create)
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 16)
                .background(CourtlyColor.surface)
        }
        .task { await load() }
        .errorAlert($errorMessage, title: "Couldn’t create the group")
    }

    /// A failed load says so instead of looking like a player with no friends.
    private func load() async {
        isLoading = true
        do {
            friends = try await API.People.friends()
            loadFailed = false
        } catch {
            loadFailed = true
        }
        isLoading = false
    }

    private func create() {
        isCreating = true
        Task { @MainActor in
            do {
                let chat = try await API.Chats.createGroup(name: name.trimmingCharacters(in: .whitespaces), memberIDs: Array(selected))
                await inbox.load()
                navigate.replaceTop(.chat(chat.id))
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}
