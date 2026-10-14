import SwiftUI

enum AccountMode: Hashable {
    case signUp, signIn
}

/// Every pushed screen in the flow, in order. Welcome is the stack root.
enum OnboardingRoute: Hashable {
    case createAccount(AccountMode)
    case name
    case birthday
    case gender
    case level
    case formats
    case location
    case availability
    case friends
    case people
    case notifications
    case done
}

/// Welcome → account → profile questions → location → availability → friends → notifications → done.
struct OnboardingFlow: View {
    @Environment(AppSession.self) private var session
    @State private var draft = OnboardingDraft()
    @State private var path: [OnboardingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onGetStarted: { path.append(.createAccount(.signUp)) },
                onSignIn: { path.append(.createAccount(.signIn)) }
            )
            .navigationDestination(for: OnboardingRoute.self) { route in
                destination(for: route)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: OnboardingRoute) -> some View {
        switch route {
        case let .createAccount(mode):
            CreateAccountView(mode: mode, draft: draft) {
                switch mode {
                case .signUp:
                    path.append(.name)
                case .signIn:
                    // Returning players will load their profile from the backend. Until then, sign-in
                    // drops into the app with what the device has.
                    session.completeOnboarding(with: draft)
                }
            }
        case .name:
            NameView(draft: draft) { path.append(.birthday) }
        case .birthday:
            BirthdayView(draft: draft) { path.append(.gender) }
        case .gender:
            GenderView(draft: draft) { path.append(.level) }
        case .level:
            LevelView(draft: draft) { path.append(.formats) }
        case .formats:
            FormatsView(draft: draft) { path.append(.location) }
        case .location:
            LocationView(draft: draft) { path.append(.availability) }
        case .availability:
            AvailabilityView(draft: draft) { path.append(.friends) }
        case .friends:
            FriendsIntroView(
                onFindFriends: { granted in
                    draft.contactsGranted = granted
                    path.append(.people)
                },
                onSkip: { path.append(.notifications) }
            )
        case .people:
            PeopleToPlayWithView(draft: draft) { path.append(.notifications) }
        case .notifications:
            NotificationsView(draft: draft) { path.append(.done) }
        case .done:
            YoureInView(firstName: draft.trimmedFirstName) {
                session.completeOnboarding(with: draft)
            }
        }
    }
}
