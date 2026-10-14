import SwiftUI

/// Chooses between the launch screen, onboarding and the main app.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        @Bindable var session = session
        Group {
            switch session.stage {
            case .loading:
                LaunchView()
                    .transition(.opacity)
            case let .onboarding(resume):
                OnboardingFlow(resumeProfile: resume)
                    .transition(.opacity)
            case .main:
                MainTabView(account: session.profile?.id)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.stage)
        .alert(item: $session.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
        }
    }
}

/// Blue field while the session is restored; the welcome screen fades in over it.
private struct LaunchView: View {
    var body: some View {
        ZStack {
            CourtlyColor.blue.ignoresSafeArea()
            Text("Courtly")
                .font(CourtlyFont.secondarySemibold)
                .tracking(0.2)
                .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
    }
}
