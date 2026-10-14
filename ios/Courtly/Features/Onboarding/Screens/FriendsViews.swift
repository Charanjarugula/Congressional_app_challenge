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
            subtitle: "See which of your contacts already play, and invite the ones who should."
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

/// 14 · People to play with. Contacts already on Courtly, then recommendations.
struct PeopleToPlayWithView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    private var contacts: [SuggestedPlayer] {
        draft.contactsGranted ? SampleData.contactsOnCourtly : []
    }

    var body: some View {
        OnboardingStepView(
            progress: 0.9,
            title: "People to play with",
            subtitle: "Add a few now so your first hit is easy to set up."
        ) {
            if !contacts.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(title: "From your contacts")
                    Spacer()
                    ShareLink(item: "Join me on Courtly, the easiest way to find a tennis partner in Palm Beach County.") {
                        Text("Invite more")
                            .font(CourtlyFont.captionSemibold)
                            .foregroundStyle(CourtlyColor.blue)
                    }
                }
                .padding(.top, 24)
                .padding(.bottom, 4)
                playerList(contacts, style: .tint)
            }

            SectionLabel(title: "Recommended for you")
                .padding(.top, 24)
                .padding(.bottom, 4)
            playerList(SampleData.recommended, style: .muted)
        } footer: {
            PrimaryButton(title: "Continue", action: onContinue)
        }
    }

    private func playerList(_ players: [SuggestedPlayer], style: InitialsAvatar.Style) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                if index > 0 {
                    HairlineSeparator()
                }
                PlayerSuggestionRow(
                    player: player,
                    avatarStyle: style,
                    isAdded: draft.addedPlayerIDs.contains(player.id)
                ) {
                    if draft.addedPlayerIDs.contains(player.id) {
                        draft.addedPlayerIDs.remove(player.id)
                    } else {
                        draft.addedPlayerIDs.insert(player.id)
                    }
                }
            }
        }
    }
}

/// 64pt row: avatar, name + level · distance, Add/Added pill.
struct PlayerSuggestionRow: View {
    let player: SuggestedPlayer
    var avatarStyle: InitialsAvatar.Style = .tint
    let isAdded: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            InitialsAvatar(initials: player.initials, size: 44, style: avatarStyle)
            VStack(alignment: .leading, spacing: 1) {
                Text(player.fullName)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                Text(player.detail)
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
