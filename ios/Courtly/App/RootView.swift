import SwiftUI

/// Chooses between onboarding and the main app based on whether a profile exists on this device.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        Group {
            switch session.stage {
            case .onboarding:
                OnboardingFlow()
                    .transition(.opacity)
            case .main:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: session.stage)
    }
}
