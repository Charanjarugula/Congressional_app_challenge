import SwiftUI

enum AccountMode: Hashable {
    case signUp, signIn
}

/// Every pushed screen in the flow, in order. Welcome is the stack root.
enum OnboardingRoute: Hashable {
    case createAccount(AccountMode)
    case emailCode(String)
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
/// A player who signed in but never finished starts again at the name step.
struct OnboardingFlow: View {
    @Environment(AppSession.self) private var session
    @State private var draft = OnboardingDraft()
    @State private var path: [OnboardingRoute]

    private let resumeProfile: Bool

    init(resumeProfile: Bool) {
        self.resumeProfile = resumeProfile
        _path = State(initialValue: resumeProfile ? [.name] : [])
    }

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
        // Welcome is blue with white status-bar text; every other screen is light. The root
        // view's preference wins inside a NavigationStack, so it has to change with the path.
        .preferredColorScheme(path.isEmpty ? .dark : .light)
        .onAppear {
            if resumeProfile, let profile = session.profile { draft.load(from: profile) }
        }
    }

    /// After any successful sign-in: into the app if the profile is finished, otherwise on to the name step.
    private func continueAfterSignIn() {
        Task { @MainActor in
            do {
                let onboarded = try await session.handleSignedIn()
                if !onboarded {
                    if let profile = session.profile { draft.load(from: profile) }
                    path.append(.name)
                }
            } catch {
                session.show(error, title: "Couldn’t load your profile")
            }
        }
    }

    @ViewBuilder
    private func destination(for route: OnboardingRoute) -> some View {
        switch route {
        case let .createAccount(mode):
            CreateAccountView(
                mode: mode,
                onSignedIn: continueAfterSignIn,
                onEmailSent: { email in path.append(.emailCode(email)) }
            )
        case let .emailCode(email):
            EmailCodeView(email: email, onSignedIn: continueAfterSignIn)
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
                try await session.completeOnboarding(with: draft, accountEmail: nil)
            }
        }
    }
}
