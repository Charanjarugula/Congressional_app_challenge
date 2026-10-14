import Contacts
import SwiftUI

/// Find players by name, from your contacts, or from who you already play with.
struct AddFriendsView: View {
    @Environment(InboxStore.self) private var inbox
    @State private var query = ""
    @State private var results: [SearchedPlayer] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var contactMatches: [ContactMatch] = []
    @State private var suggestions: [SuggestedPlayer] = []
    @State private var friendIDs: Set<UUID> = []
    @State private var isLoadingSuggestions = true
    @State private var contactsAllowed = Self.contactsAuthorized
    @State private var relationships: [UUID: Relationship] = [:]
    @State private var adding: UUID?
    @State private var errorMessage: String?
    @FocusState private var searchFocused: Bool

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                searchRow
                if !trimmedQuery.isEmpty {
                    SectionHeader(title: isSearching ? "Searching…" : "Results", top: 20)
                    if results.isEmpty {
                        if !isSearching {
                            QuietCard(title: "No one named “\(trimmedQuery)”", detail: "Players show up by first name once they’ve joined Courtly.")
                        }
                    } else {
                        CardRows(items: results) { result in
                            personRow(result.card, subtitle: subtitle(for: result), relationship: relationship(for: result.card.id, fallback: result.relationship))
                        }
                    }
                }
                if !contactsAllowed {
                    contactsPrompt
                } else if !contactMatches.isEmpty {
                    SectionHeader(title: "From your contacts", top: 24)
                    CardRows(items: contactMatches.map(\.player)) { card in
                        personRow(card, subtitle: card.levelAndArea.isEmpty ? "In your contacts" : card.levelAndArea, relationship: relationship(for: card.id, fallback: friendIDs.contains(card.id) ? .friend : .none))
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
                    CardRows(items: suggestions) { suggestion in
                        personRow(suggestion.card, subtitle: suggestion.reason ?? suggestion.card.levelAndArea, relationship: relationship(for: suggestion.id, fallback: .none))
                    }
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .navigationTitle("Add friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        .task { await loadSuggestions() }
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
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CourtlyColor.separator))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(CourtlyColor.blue, lineWidth: searchFocused ? 2 : 0)
            )
            if searchFocused || !query.isEmpty {
                Button("Cancel") {
                    query = ""
                    searchFocused = false
                }
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.blue)
            }
        }
        .frame(height: 52)
        .animation(.easeInOut(duration: 0.15), value: searchFocused)
    }

    private var contactsPrompt: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "From your contacts", top: 24)
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Find friends who are already here. Only hashed numbers are sent, never stored.")
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(CourtlyColor.secondary)
                    ActionButton(title: "Check my contacts") {
                        Task { await allowContacts() }
                    }
                }
            }
        }
    }

    private func personRow(_ card: PlayerCard, subtitle: String, relationship: Relationship) -> some View {
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
            PillButton(title: "Requested", style: .tint) {}
                .disabled(true)
        case .requestedMe:
            PillButton(title: adding == card.id ? "Adding…" : "Add back") { add(card) }
                .disabled(adding != nil)
        case .none, .blocked:
            PillButton(title: adding == card.id ? "Adding…" : "Add") { add(card) }
                .disabled(adding != nil)
        }
    }

    private func subtitle(for result: SearchedPlayer) -> String {
        if !result.mutualFriends.isEmpty {
            let names = result.mutualFriends.prefix(2).joined(separator: " and ")
            return "Friends with \(names)"
        }
        return result.card.levelAndArea.isEmpty ? "On Courtly" : result.card.levelAndArea
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
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func loadSuggestions() async {
        defer { isLoadingSuggestions = false }
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
