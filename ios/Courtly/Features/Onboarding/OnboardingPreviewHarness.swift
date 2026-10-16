#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Simulator-only UI test entry point. Uses the real views with local draft state and no save callbacks.
/// Never compiled into a device/TestFlight build; does not bypass production authentication.
struct OnboardingPreviewHarness: View {
    @State private var draft = OnboardingDraft()
    @State private var advanced = false
    private let screens = ["Name", "Birthday", "Level", "Formats", "Location", "Availability", "Players", "Notifications", "Done"]

    var body: some View {
        NavigationStack {
            List(screens, id: \.self) { screen in
                NavigationLink(screen, value: screen)
            }
            .navigationTitle("Onboarding UI checks")
            .navigationDestination(for: String.self) { screen in
                Group {
                    if advanced {
                        Text("Advanced").foregroundStyle(.white)
                    } else {
                        destination(screen)
                    }
                }
                .environment(\.colorScheme, .light)
                .background(CourtlyColor.blue.ignoresSafeArea())
                .onDisappear { advanced = false }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func destination(_ screen: String) -> some View {
        switch screen {
        case "Name": NameView(draft: draft) { advanced = true }
        case "Birthday": BirthdayView(previewDraft: draft) { advanced = true }
        case "Level": LevelView(draft: draft) { advanced = true }
        case "Formats": FormatsView(draft: draft) { advanced = true }
        case "Location": LocationView(draft: draft) { advanced = true }
        case "Availability": AvailabilityView(draft: draft) { advanced = true }
        case "Players": PeopleToPlayWithView(draft: draft) { advanced = true }
        case "Notifications": NotificationsView(draft: draft) { advanced = true }
        default: YoureInView(firstName: "Sam") { advanced = true }
        }
    }
}
#endif
