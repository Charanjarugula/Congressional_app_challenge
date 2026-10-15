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

/// 14 · Players near you. What is going on nearby, then contacts already on Courtly, then players near
/// you. Adding sends a friend request right away; tapping Requested takes it back.
struct PeopleToPlayWithView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var pulse: AreaPulse?
    @State private var contacts: [PersonSuggestion] = []
    @State private var nearby: [PersonSuggestion] = []
    @State private var requested: Set<UUID> = []
    @State private var busy: Set<UUID> = []   // one request per person at a time, so Add then Requested can't cross
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        OnboardingStepView(
            progress: 0.9,
            title: "Players near you",
            subtitle: subtitle
        ) {
            if isLoading {
                ProgressView()
                    .tint(CourtlyColor.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
            } else {
                if let pulse {
                    PulseTiles(pulse: pulse)
                        .padding(.top, 20)
                }

                if !contacts.isEmpty {
                    SectionLabel(title: "From your contacts")
                        .padding(.top, 24)
                        .padding(.bottom, 4)
                    playerList(contacts)
                }

                if !nearby.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        SectionLabel(title: contacts.isEmpty ? "Say hi to a few" : "Also near you")
                        Spacer()
                        inviteLink
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 4)
                    playerList(nearby)
                }

                // Only when the lists really came back empty; a failed load says so below instead.
                if contacts.isEmpty && nearby.isEmpty && errorMessage == nil {
                    firstHere
                        .padding(.top, 24)
                }

                if let errorMessage {
                    ErrorCaption(text: errorMessage)
                        .padding(.top, 12)
                }
            }
        } footer: {
            PrimaryButton(title: requested.isEmpty ? "Continue" : "Continue · \(requested.count) requested", action: onContinue)
        }
        .task { await load() }
    }

    private var subtitle: String {
        guard let town = pulse?.town else { return "Add a few people now so your first hit is easy to set up." }
        return "Here’s who plays around \(town). Add a few so your first hit is easy to set up."
    }

    /// Nobody nearby yet: say so plainly, and make inviting a partner the next step.
    private var firstHere: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You’re one of the first players\(pulse?.town.map { " around \($0)" } ?? " here")")
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(CourtlyColor.ink)
            Text("Invite the people you already hit with. Once they join, their hits show up on Play and yours show up for them.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ShareLink(item: inviteText) {
                Text("Invite a hitting partner")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Capsule().fill(CourtlyColor.lime))
            }
            .padding(.top, 8)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: CourtlyMetrics.cardRadius, style: .continuous).fill(CourtlyColor.groupedBackground))
    }

    private var inviteText: String {
        "Join me on Courtly, the easiest way to find a tennis partner\(pulse?.town.map { " around \($0)" } ?? "")."
    }

    private var inviteLink: some View {
        ShareLink(item: inviteText) {
            Text("Invite more")
                .font(CourtlyFont.captionSemibold)
                .foregroundStyle(CourtlyColor.blue)
        }
    }

    private func playerList(_ people: [PersonSuggestion]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(people.enumerated()), id: \.element.id) { index, person in
                if index > 0 {
                    HairlineSeparator()
                }
                PlayerSuggestionRow(
                    card: person.card,
                    name: person.displayName,
                    detail: person.detail,
                    isAdded: requested.contains(person.id)
                ) {
                    toggle(person.card.id)
                }
            }
        }
    }

    private func load() async {
        async let pulseCall = try? API.People.areaPulse()
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
            nearby = suggestions
                .filter { !knownIDs.contains($0.id) }
                .map { PersonSuggestion(card: $0.card, displayName: $0.card.displayName, detail: $0.reason ?? $0.card.levelAndArea) }
        } catch {
            errorMessage = "Couldn’t load players near you. \(error.localizedDescription)"
        }
        pulse = await pulseCall
        isLoading = false
    }

    private func toggle(_ id: UUID) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        let wasRequested = requested.contains(id)
        if wasRequested { requested.remove(id) } else { requested.insert(id) }
        Task { @MainActor in
            defer { busy.remove(id) }
            do {
                if wasRequested {
                    _ = try await API.People.cancelFriendRequest(id)
                } else {
                    _ = try await API.People.addFriend(id)
                }
            } catch {
                if wasRequested { requested.insert(id) } else { requested.remove(id) }
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Three numbers that show the app is alive nearby: players, open hits this week, courts.
struct PulseTiles: View {
    let pulse: AreaPulse

    var body: some View {
        HStack(spacing: 10) {
            tile(pulse.players, pulse.players == 1 ? "player" : "players")
            tile(pulse.openHits, pulse.openHits == 1 ? "open hit this week" : "open hits this week")
            tile(pulse.courts, pulse.courts == 1 ? "court" : "courts")
        }
        .accessibilityElement(children: .combine)
        .overlay(alignment: .bottomLeading) {
            Text("Within \(pulse.radiusMi) mi")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .offset(y: 22)
        }
        .padding(.bottom, 22)
    }

    private func tile(_ value: Int, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(CourtlyFont.rounded(26))
                .foregroundStyle(CourtlyColor.ink)
            Text(label)
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CourtlyColor.groupedBackground))
    }
}

/// 64pt row: photo or initials, name and why they're suggested, Add / Requested.
struct PlayerSuggestionRow: View {
    let card: PlayerCard
    let name: String
    let detail: String
    let isAdded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            PlayerAvatar(card: card, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            PillButton(
                title: isAdded ? "Requested" : "Add",
                style: isAdded ? .tint : .filled,
                action: onToggle
            )
        }
        .frame(height: 64)
    }
}
