import SwiftUI

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
    /// Where the player stands with each person shown: from contact matches, then from taps here.
    @State private var standings: [UUID: Relationship] = [:]
    private var requestedCount: Int { standings.values.filter { $0 == .requested }.count }
    @State private var busy: Set<UUID> = []   // one request per person at a time, so Add then Requested can't cross
    @State private var isLoading = true
    @State private var isCheckingContacts = false
    @State private var errorMessage: String?
    @State private var pendingRequest: PendingFriendRequest?

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

                // Tapping this goes straight to the system prompt: no pre-prompt screen with a way out.
                if !draft.contactsGranted {
                    Button(action: findContacts) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(CourtlyColor.blue)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Find friends from contacts")
                                    .font(CourtlyFont.bodySemibold)
                                    .foregroundStyle(CourtlyColor.ink)
                                Text("See who already plays. Only hashed email addresses are checked.")
                                    .font(CourtlyFont.caption)
                                    .foregroundStyle(CourtlyColor.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            if isCheckingContacts { ProgressView().tint(CourtlyColor.secondary) }
                        }
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: CourtlyMetrics.cardRadius, style: .continuous).fill(CourtlyColor.groupedBackground))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isCheckingContacts)
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
            PrimaryButton(title: requestedCount == 0 ? "Continue" : "Continue · \(requestedCount) requested", action: onContinue)
        }
        .task { await load() }
        .takeBackRequestDialog($pendingRequest) { toggle($0) }
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
                    standing: standings[person.id] ?? Relationship.none
                ) {
                    if standings[person.id] == .requested {
                        pendingRequest = PendingFriendRequest(id: person.card.id, firstName: person.card.firstName)
                    } else {
                        toggle(person.card.id)
                    }
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
                // Anyone already asked shows Requested, not a second Add.
                for match in matches { if let r = match.relationship, r != .none { standings[match.player.id] = r } }
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

    /// Asks for contacts only when the player taps the button, then reloads with any matches on top.
    private func findContacts() {
        guard !isCheckingContacts else { return }
        isCheckingContacts = true
        Task { @MainActor in
            let granted = await ContactsService().requestAccess()
            draft.contactsGranted = true   // asked once; the button goes away either way
            if granted { await load() }
            isCheckingContacts = false
        }
    }

    private func toggle(_ id: UUID) {
        guard !busy.contains(id) else { return }
        busy.insert(id)
        let before = standings[id] ?? Relationship.none
        guard before != .friend && before != .blocked else { busy.remove(id); return }
        // Requested → take it back; anything else → add (adding someone who asked you accepts them).
        standings[id] = before == .requested ? Relationship.none : .requested
        Task { @MainActor in
            defer { busy.remove(id) }
            do {
                if before == .requested {
                    _ = try await API.People.cancelFriendRequest(id)
                } else {
                    let result = try await API.People.addFriend(id)
                    standings[id] = Relationship(rawValue: result.relationship) ?? .requested
                }
            } catch {
                standings[id] = before
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Two numbers that show the app is alive nearby: players and open hits this week.
struct PulseTiles: View {
    let pulse: AreaPulse

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                tile(pulse.players, pulse.players == 1 ? "player nearby" : "players nearby", icon: "person.2.fill")
                tile(pulse.openHits, pulse.openHits == 1 ? "open hit this week" : "open hits this week", icon: "tennisball.fill")
            }
            Text(pulse.town.map { "Around \($0)" } ?? "In your area")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.horizontal, 2)
        }
        .accessibilityElement(children: .combine)
    }

    private func tile(_ value: Int, _ label: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CourtlyColor.blue)
                .frame(width: 36, height: 36)
                .background(Circle().fill(CourtlyColor.blueTint))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(value)")
                    .font(CourtlyFont.rounded(24))
                    .foregroundStyle(CourtlyColor.ink)
                Text(label)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CourtlyColor.groupedBackground))
    }
}

/// 64pt row: photo or initials, name and why they're suggested, Add / Requested.
struct PlayerSuggestionRow: View {
    let card: PlayerCard
    let name: String
    let detail: String
    let standing: Relationship
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
            switch standing {
            case .friend:
                PillButton(title: "Friends", style: .tint, showsCheck: true) {}
                    .disabled(true)
            case .requested:
                PillButton(title: "Requested", style: .tint, action: onToggle)
            case .requestedMe:
                PillButton(title: "Confirm", style: .filled, action: onToggle)
            case .none, .blocked:
                PillButton(title: "Add", style: .filled, action: onToggle)
            }
        }
        .frame(height: 64)
    }
}
