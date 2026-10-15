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
    case level
    case formats
    case location
    case availability
    case people
    case notifications
    case done
}

/// Welcome → account → profile questions → location → availability → players near you → notifications → done.
/// A player who signed in but never finished starts again at the name step.
struct OnboardingFlow: View {
    @Environment(AppSession.self) private var session
    @State private var draft = OnboardingDraft()
    @State private var path: [OnboardingRoute]
    @State private var showsWelcomeScheme: Bool

    private let resumeProfile: Bool

    init(resumeProfile: Bool) {
        self.resumeProfile = resumeProfile
        _path = State(initialValue: resumeProfile ? [.name] : [])
        _showsWelcomeScheme = State(initialValue: !resumeProfile)
    }

    /// Pushes once, however fast Continue is tapped.
    private func push(_ route: OnboardingRoute) {
        guard path.last != route else { return }
        path.append(route)
    }

    /// Profile answers are saved as they are given, so quitting mid-way loses nothing.
    private func save(then route: OnboardingRoute) {
        session.saveDraft(draft)
        push(route)
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onGetStarted: { push(.createAccount(.signUp)) },
                onSignIn: { push(.createAccount(.signIn)) }
            )
            .navigationDestination(for: OnboardingRoute.self) { route in
                destination(for: route)
            }
        }
        // Welcome is blue with white status-bar text; every other screen is light. The root
        // view's preference wins inside a NavigationStack, so it follows the path, switching
        // once the push animation has carried Welcome off screen.
        .preferredColorScheme(showsWelcomeScheme ? .dark : .light)
        .onChange(of: path.isEmpty) { _, atWelcome in
            if atWelcome {
                showsWelcomeScheme = true
            } else {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    if !path.isEmpty { showsWelcomeScheme = false }
                }
            }
        }
        .onAppear {
            if resumeProfile, let profile = session.profile { draft.load(from: profile) }
        }
    }

    /// After any successful sign-in: into the app if the profile is finished, otherwise on to the
    /// name step, prefilled with what the profile or Apple already knows.
    @MainActor
    private func continueAfterSignIn(name: PersonNameComponents?) async {
        do {
            let onboarded = try await session.handleSignedIn()
            if !onboarded {
                if let profile = session.profile { draft.load(from: profile) }
                if draft.trimmedFirstName.isEmpty, let given = name?.givenName {
                    draft.firstName = given
                    draft.lastName = name?.familyName ?? ""
                }
                push(.name)
            }
        } catch {
            session.show(error, title: "Couldn’t load your profile")
        }
    }

    @ViewBuilder
    private func destination(for route: OnboardingRoute) -> some View {
        switch route {
        case let .createAccount(mode):
            CreateAccountView(
                mode: mode,
                onSignedIn: { name in await continueAfterSignIn(name: name) },
                onEmailSent: { email in push(.emailCode(email)) }
            )
        case let .emailCode(email):
            EmailCodeView(email: email, onSignedIn: { await continueAfterSignIn(name: nil) })
        case .name:
            NameView(draft: draft) { save(then: .birthday) }
        case .birthday:
            BirthdayView(draft: draft) { save(then: .level) }
        case .level:
            LevelView(draft: draft) { save(then: .formats) }
        case .formats:
            FormatsView(draft: draft) { save(then: .location) }
        case .location:
            LocationView(draft: draft) { save(then: .availability) }
        case .availability:
            AvailabilityView(draft: draft) { save(then: .people) }
        case .people:
            PeopleToPlayWithView(draft: draft) { push(.notifications) }
        case .notifications:
            NotificationsView(draft: draft) { push(.done) }
        case .done:
            YoureInView(firstName: draft.trimmedFirstName) {
                try await session.completeOnboarding(with: draft)
            }
        }
    }
}
