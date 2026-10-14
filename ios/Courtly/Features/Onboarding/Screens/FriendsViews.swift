import SwiftUI

/// 13 · Find friends. Asks for contacts access, then moves to the people list either way.
struct FriendsIntroView: View {
    let onFindFriends: (_ contactsGranted: Bool) -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false

    private let sampleInitials: [(String, InitialsAvatar.Style)] = [
        ("JT", .tint), ("AO", .muted), ("MR", .blue), ("SP", .muted),
    ]

    var body: some View {
        OnboardingStepView(
            progress: 0.9,
            title: "Tennis is better with friends.",
            subtitle: "See which of your contacts already play (matched by email, and by phone once you add your number), and invite the ones who should."
        ) {
            HStack(spacing: -8) {
                ForEach(Array(sampleInitials.enumerated()), id: \.offset) { _, item in
                    InitialsAvatar(initials: item.0, size: 64, style: item.1, ringed: true)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .accessibilityHidden(true)
        } footer: {
            VStack(spacing: 4) {
                PrimaryButton(title: "Find friends from contacts", isLoading: isRequesting, action: requestContacts)
                TextActionButton(title: "Not now", action: onSkip)
            }
        }
    }

    private func requestContacts() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { @MainActor in
            let granted = await ContactsService().requestAccess()
            isRequesting = false
            onFindFriends(granted)
        }
    }
}

/// A row on the people list: the player, why they are suggested, and whether we already added them.
struct PersonSuggestion: Identifiable {
    let card: PlayerCard
    let displayName: String     // the address-book name for contacts, otherwise "Priya S."
    let detail: String
    var id: UUID { card.id }
}

/// 14 · People to play with. Contacts already on Courtly, then recommendations. Adds happen immediately.
struct PeopleToPlayWithView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var contacts: [PersonSuggestion] = []
    @State private var recommended: [PersonSuggestion] = []
    @State private var added: Set<UUID> = []
    @State private var busy: Set<UUID> = []   // one request per person at a time, so Add then Added can't cross
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        OnboardingStepView(
            progress: 0.9,
            title: "People to play with",
            subtitle: "Add a few now so your first hit is easy to set up."
        ) {
            if isLoading {
                ProgressView()
                    .tint(CourtlyColor.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            } else {
                if !contacts.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(title: "From your contacts")
                        Spacer()
                        inviteLink
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 4)
                    playerList(contacts, style: .tint)
                }

                if !recommended.isEmpty {
                    SectionLabel(title: "Recommended for you")
                        .padding(.top, 24)
                        .padding(.bottom, 4)
                    playerList(recommended, style: .muted)
                }

                if contacts.isEmpty && recommended.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(draft.contactsGranted ? "None of your contacts are on Courtly yet." : "No suggestions yet.")
                            .font(CourtlyFont.bodySemibold)
                            .foregroundStyle(CourtlyColor.ink)
                        Text("You can add people from a hit or from People once you’re in.")
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.secondary)
                        inviteLink
                            .padding(.top, 8)
                    }
                    .padding(.top, 28)
                }

                if let errorMessage {
                    ErrorCaption(text: errorMessage)
                        .padding(.top, 12)
                }
            }
        } footer: {
            PrimaryButton(title: "Continue", action: onContinue)
        }
        .task { await load() }
    }

    private var inviteLink: some View {
        ShareLink(item: "Join me on Courtly, the easiest way to find a tennis partner in Palm Beach County.") {
            Text("Invite more")
                .font(CourtlyFont.captionSemibold)
                .foregroundStyle(CourtlyColor.blue)
        }
    }

    private func playerList(_ people: [PersonSuggestion], style: InitialsAvatar.Style) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    HairlineSeparator()
                }
                PlayerSuggestionRow(
                    name: person.displayName,
                    detail: person.detail,
                    initials: person.card.initials,
                    avatarStyle: style,
                    isAdded: added.contains(person.id)
                ) {
                    toggle(person.card.id)
                }
            }
        }
    }

    private func load() async {
        var knownIDs: [UUID] = []
        if draft.contactsGranted {
            do {
                let hashed = try await Task.detached(priority: .userInitiated) { try ContactsService().hashedContacts() }.value
                let byHash = Dictionary(hashed.map { ($0.hash, $0.displayName) }, uniquingKeysWith: { first, _ in first })
                let matches = try await API.People.matchContacts(hashes: hashed.map(\.hash))
                var seen = Set<UUID>()
                contacts = matches.compactMap { match in
                    guard seen.insert(match.player.id).inserted else { return nil }
                    return PersonSuggestion(
                        card: match.player,
                        displayName: byHash[match.hash] ?? match.player.displayName,
                        detail: match.player.levelAndArea
                    )
                }
                knownIDs = contacts.map(\.id)
            } catch {
                errorMessage = "Couldn’t check your contacts. \(error.localizedDescription)"
            }
        }
        do {
            let suggestions = try await API.People.suggestions(knownIDs: knownIDs)
            recommended = suggestions
                .filter { suggestion in !knownIDs.contains(suggestion.id) }
                .map { PersonSuggestion(card: $0.card, displayName: $0.card.displayName, detail: $0.reason ?? $0.card.levelAndArea) }
        } catch {
            errorMessage = "Couldn’t load suggestions. \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func toggle(_ id: UUID) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        let wasAdded = added.contains(id)
        if wasAdded { added.remove(id) } else { added.insert(id) }
        Task { @MainActor in
            defer { busy.remove(id) }
            do {
                if wasAdded {
                    try await API.People.removeFriend(id)
                } else {
                    _ = try await API.People.addFriend(id)
                }
            } catch {
                if wasAdded { added.insert(id) } else { added.remove(id) }
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// 64pt row: avatar, name + level · distance, Add/Added pill.
struct PlayerSuggestionRow: View {
    let name: String
    let detail: String
    let initials: String
    var avatarStyle: InitialsAvatar.Style = .tint
    let isAdded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialsAvatar(initials: initials, size: 44, style: avatarStyle)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                Text(detail)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
            }
            Spacer(minLength: 8)
            PillButton(
                title: isAdded ? "Added" : "Add",
                style: isAdded ? .tint : .filled,
                showsCheck: isAdded,
                action: onToggle
            )
        }
        .frame(height: 64)
    }
}
