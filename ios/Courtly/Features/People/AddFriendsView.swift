import Contacts
import SwiftUI

/// Find players by name, from your contacts, or from who you already play with.
struct AddFriendsView: View {
    @Environment(InboxStore.self) private var inbox
    @Environment(\.navigate) private var navigate
    @State private var query = ""
    @State private var results: [SearchedPlayer] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var contactMatches: [ContactMatch] = []
    @State private var suggestions: [SuggestedPlayer] = []
    @State private var friendIDs: Set<UUID> = []
    @State private var isLoadingSuggestions = true
    @State private var contactsAllowed = Self.contactsAuthorized
    @State private var relationships: [UUID: Relationship] = [:]
    @State private var adding: UUID?
    @State private var errorMessage: String?
    @State private var pendingRequest: PendingFriendRequest?
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchRow
                if !trimmedQuery.isEmpty {
                    SectionHeader(title: isSearching ? "Searching…" : "Results", top: 20)
                    if results.isEmpty {
                        if let searchError {
                            QuietCard(title: "Couldn’t search", detail: searchError)
                        } else if !isSearching {
                            QuietCard(title: "No one named “\(trimmedQuery)”", detail: "Players show up by first name once they’ve joined Courtly.")
                        }
                    } else {
                        CardRows(items: results, radius: 22) { result in
                            personRow(result.card, subtitle: subtitle(for: result), relationship: relationship(for: result.card.id, fallback: result.relationship))
                        }
                    }
                }
                if !contactsAllowed {
                    contactsPrompt
                } else if !contactMatches.isEmpty {
                    SectionHeader(title: "From your contacts", top: 24)
                    CardRows(items: contactMatches.map(\.player), radius: 22) { card in
                        personRow(card, subtitle: card.levelAndArea.isEmpty ? "In your contacts" : card.levelAndArea, relationship: relationship(for: card.id, fallback: contactRelationship(card.id)))
                    }
                }
                SectionHeader(title: "Suggested for you", top: 24)
                if isLoadingSuggestions {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if suggestions.isEmpty {
                    QuietCard(title: "No suggestions yet", detail: "Add a friend or join a hit and people you cross paths with show up here.")
                } else {
                    CardRows(items: suggestions, radius: 22) { suggestion in
                        personRow(suggestion.card, subtitle: suggestion.mutualFriends.mutualLabel ?? suggestion.reason ?? suggestion.card.levelAndArea, relationship: relationship(for: suggestion.id, fallback: .none))
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.surface.ignoresSafeArea())
        .plainBackButton()
        .navigationTitle("Add friends")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .task { await loadSuggestions() }
        .takeBackRequestDialog($pendingRequest) { cancelRequest($0) }
        .errorAlert($errorMessage)
    }

    // MARK: - Pieces

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CourtlyColor.secondary)
                TextField("Search by name", text: $query)
                    .font(CourtlyFont.body)
                    .autocorrectionDisabled()
                    .focused($searchFocused)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CourtlyColor.card))
            if searchFocused || !query.isEmpty {
                Button("Cancel") {
                    query = ""
                    searchFocused = false
                }
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.blue)
            }
        }
        .frame(minHeight: 56)
        .animation(.easeInOut(duration: 0.15), value: searchFocused)
    }

    private var contactsPrompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "From your contacts", top: 24)
            Card(padding: 16, radius: 22) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Find friends who are already here. Only hashed email addresses are checked; your address book is never uploaded.")
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(CourtlyColor.secondary)
                    ActionButton(title: "Check my contacts") {
                        Task { await allowContacts() }
                    }
                }
            }
        }
    }

    /// Tapping the photo or name opens their profile; the button on the right is separate.
    private func personRow(_ card: PlayerCard, subtitle: String, relationship: Relationship) -> some View {
        HStack(spacing: 14) {
            Button { navigate(.player(card.id)) } label: {
                HStack(spacing: 14) {
                    PlayerAvatar(card: card, size: 48)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(card.displayName)
                            .font(CourtlyFont.bodySemibold)
                            .foregroundStyle(CourtlyColor.ink)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens their profile")
            addButton(for: card, relationship: relationship)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func addButton(for card: PlayerCard, relationship: Relationship) -> some View {
        switch relationship {
        case .friend:
            PillButton(title: "Added", style: .tint, showsCheck: true) {}
                .disabled(true)
        case .requested:
            PillButton(title: "Requested", style: .tint) {
                pendingRequest = PendingFriendRequest(id: card.id, firstName: card.firstName)
            }
                .disabled(adding != nil)
        case .requestedMe:
            PillButton(title: adding == card.id ? "Confirming…" : "Confirm") { respond(card, accept: true) }
                .disabled(adding != nil)
        case .none, .blocked:
            PillButton(title: adding == card.id ? "Adding…" : "Add") { add(card) }
                .disabled(adding != nil)
        }
    }

    private func subtitle(for result: SearchedPlayer) -> String {
        if let mutual = result.mutualFriends.mutualLabel { return mutual }
        return result.card.levelAndArea.isEmpty ? "On Courtly" : result.card.levelAndArea
    }

    /// What the server said about a contact match, with friends known from the friend list.
    private func contactRelationship(_ id: UUID) -> Relationship {
        if friendIDs.contains(id) { return .friend }
        return contactMatches.first { $0.player.id == id }?.relationship ?? Relationship.none
    }

    private func relationship(for id: UUID, fallback: Relationship) -> Relationship {
        relationships[id] ?? (friendIDs.contains(id) ? .friend : fallback)
    }

    // MARK: - Data

    private static var contactsAuthorized: Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if status == .authorized { return true }
        if #available(iOS 18, *), status == .limited { return true }
        return false
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        searchError = nil
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let found = try await API.People.search(trimmed)
                guard !Task.isCancelled else { return }
                results = found
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchError = error.localizedDescription   // inline, under the field; a modal per keystroke would be noise
            }
            isSearching = false
        }
    }

    /// Runs each time the screen appears, including coming back from a profile where a request may
    /// have been sent or taken back, so every row shows the server's answer again.
    private func loadSuggestions() async {
        defer { isLoadingSuggestions = false }
        relationships = [:]
        if trimmedQuery.count >= 2 { scheduleSearch(query) }
        if let friends = try? await API.People.friends() {
            friendIDs = Set(friends.map(\.id))
        }
        if contactsAllowed {
            await matchContacts()
        }
        let known = contactMatches.map(\.player.id)
        suggestions = (try? await API.People.suggestions(knownIDs: known)) ?? []
    }

    private func allowContacts() async {
        let granted = await ContactsService().requestAccess()
        contactsAllowed = granted
        guard granted else {
            errorMessage = "Contacts access is off. You can turn it on in Settings."
            return
        }
        await matchContacts()
    }

    private func matchContacts() async {
        let hashed = (try? await Task.detached(priority: .userInitiated) { try ContactsService().hashedContacts() }.value) ?? []
        guard !hashed.isEmpty else { return }
        if let matches = try? await API.People.matchContacts(hashes: hashed.map(\.hash)) {
            var seen = Set<UUID>()
            contactMatches = matches.filter { seen.insert($0.player.id).inserted }
        }
    }

    private func respond(_ card: PlayerCard, accept: Bool) {
        adding = card.id
        Task { @MainActor in
            do {
                let result = try await API.People.respondFriendRequest(card.id, accept: accept)
                relationships[card.id] = Relationship(rawValue: result.relationship) ?? Relationship.none
                inbox.removeRequest(from: card.id)
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            adding = nil
        }
    }

    /// Tapping "Requested", then confirming, takes the request back.
    private func cancelRequest(_ id: UUID) {
        adding = id
        Task { @MainActor in
            do {
                _ = try await API.People.cancelFriendRequest(id)
                relationships[id] = Relationship.none   // explicit: a bare .none would delete the entry
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            adding = nil
        }
    }

    private func add(_ card: PlayerCard) {
        adding = card.id
        Task { @MainActor in
            do {
                let result = try await API.People.addFriend(card.id)
                relationships[card.id] = Relationship(rawValue: result.relationship) ?? .requested
                await inbox.load()
            } catch {
                errorMessage = error.localizedDescription
            }
            adding = nil
        }
    }
}
