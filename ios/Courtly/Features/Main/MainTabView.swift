import SwiftUI

/// Temporary shell for the four tabs so onboarding has somewhere to land.
/// Each tab is replaced by its designed screens in later PRs.
struct MainTabView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView {
            PlaceholderTab(
                title: "Play",
                message: "No hits planned",
                detail: "Pick a time and a court. Players nearby can ask to join."
            )
            .tabItem { Label("Play", systemImage: "figure.tennis") }

            PlaceholderTab(
                title: "My Hits",
                message: "Nothing planned",
                detail: "Join a hit on Play or post your own."
            )
            .tabItem { Label("My Hits", systemImage: "calendar") }

            PlaceholderTab(
                title: "People",
                message: "No chats yet",
                detail: "Friends and hits you join show up here."
            )
            .tabItem { Label("People", systemImage: "person.2") }

            YouSummaryView()
                .tabItem { Label("You", systemImage: "person.crop.circle") }
        }
        .tint(CourtlyColor.blue)
        .preferredColorScheme(.light)
        .task { await NotificationPermission.registerIfAuthorized() }
        .onChange(of: scenePhase) { _, phase in
            // A push token the server didn't take (offline, a hiccup) goes again when the app comes back.
            if phase == .active { Task { await API.Devices.retryPending() } }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let message: String
    let detail: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                Text(message)
                    .font(CourtlyFont.sectionHeader)
                    .foregroundStyle(CourtlyColor.ink)
                Text(detail)
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CourtlyColor.groupedBackground.ignoresSafeArea())
            .navigationTitle(title)
        }
    }
}

/// Shows the saved profile so it can be checked on device, plus a way to run onboarding again.
private struct YouSummaryView: View {
    @Environment(AppSession.self) private var session
    @State private var isSigningOut = false

    var body: some View {
        NavigationStack {
            List {
                if let profile = session.profile {
                    Section("Profile") {
                        LabeledContent("Name", value: profile.displayName)
                        LabeledContent("Shown to others as", value: profile.publicName)
                        LabeledContent("Birthday", value: profile.birthday ?? "—")
                        LabeledContent("Gender", value: profile.gender?.title ?? "—")
                        LabeledContent("Level", value: profile.level?.title ?? "—")
                        LabeledContent("What you play", value: profile.formats.map(\.shortTitle).joined(separator: ", "))
                        LabeledContent("Area", value: areaText(profile))
                        LabeledContent("Availability", value: profile.availability.shortDescription)
                        LabeledContent("Calendar", value: profile.calendarProvider == .none ? "Not connected" : profile.calendarProvider.rawValue.capitalized)
                        LabeledContent("Hits played", value: String(profile.hitsPlayed))
                    }
                }
                Section {
                    Button(isSigningOut ? "Signing out…" : "Sign out", role: .destructive) {
                        isSigningOut = true
                        Task { @MainActor in
                            await session.signOut()
                            isSigningOut = false
                        }
                    }
                    .disabled(isSigningOut)
                }
            }
            .navigationTitle("You")
            .refreshable { await session.refreshProfile() }
        }
    }

    private func areaText(_ profile: Profile) -> String {
        guard let label = profile.areaLabel else { return "Not set" }
        return "\(label) · \(profile.radius.title)"
    }
}
