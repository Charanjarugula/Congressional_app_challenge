import SwiftUI
import UIKit
import UserNotifications

/// Everything about you on one scrolling page: photo, name and contact details, how you play,
/// notifications and privacy, help, and the account actions at the bottom. Tap a row to change it.
struct YouView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: ProfileSheet?
    @State private var notificationsOn = false
    @State private var email: String?
    @State private var showsDeleteAlert = false
    @State private var isDeleting = false
    @State private var isSigningOut = false
    @State private var errorMessage: String?
    @State private var supportCopied = false
    @State private var visibilitySave: Task<Void, Never>?   // saves run in the order chosen

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let profile = session.profile {
                    content(profile)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { TabHeader(title: "Settings", art: .you) }
        .refreshable { await session.refreshProfile() }
        .sheet(item: $sheet) { which in
            switch which {
            case .name: NameSheet()
            case .availability: AvailabilitySheet()
            case .level: LevelSheet()
            case .formats: FormatsSheet()
            case .area: AreaSheet()
            }
        }
        .task {
            email = await session.currentSession()?.email
            await refreshNotificationStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshNotificationStatus() }
            }
        }
        .alert("Delete Account?", isPresented: $showsDeleteAlert) {
            Button("Delete", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, photo, friendships, direct messages and sign-in are deleted right away. Messages you sent in group or hit chats stay for the other players, without your name. This can’t be undone.")
        }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Deleting…")
                        .padding(24)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                }
            }
        }
        .errorAlert($errorMessage)
        .alert("Email us", isPresented: $supportCopied) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Mail isn’t set up on this iPhone. We copied \(AppConfig.supportEmail) so you can paste it into any email app.")
        }
    }

    @ViewBuilder
    private func content(_ profile: Profile) -> some View {
        ProfilePhotoButton(card: profile.card)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
            .padding(.bottom, 8)

        group {
            SettingsRow(title: "Name", value: profile.displayName.isEmpty ? "Add" : "\(profile.firstName) \(profile.lastName)") { sheet = .name }
            HairlineSeparator()
            // The sign-in address: shown, not editable.
            ValueRow(title: "Email", value: email ?? "—")
        }

        group(label: "Tennis") {
            SettingsRow(title: "Level", value: profile.level?.title ?? "Not set") { sheet = .level }
            HairlineSeparator()
            SettingsRow(title: "Plays", value: profile.formats.isEmpty ? "Not set" : profile.formats.map(\.shortTitle).joined(separator: ", ")) { sheet = .formats }
            HairlineSeparator()
            SettingsRow(title: "Area", value: areaValue(profile)) { sheet = .area }
            HairlineSeparator()
            SettingsRow(title: "Availability", value: profile.availability.isEmpty ? "Not set" : nil) { sheet = .availability }
        }

        group(label: "Notifications and privacy") {
            HStack {
                Text("Notifications")
                    .font(CourtlyFont.body)
                    .foregroundStyle(CourtlyColor.ink)
                Spacer()
                Toggle("Notifications", isOn: Binding(get: { notificationsOn }, set: { setNotifications($0) }))
                    .labelsHidden()
                    .tint(CourtlyColor.green)
                    .allowsHitTesting(false)   // the row takes the tap, so one tap never flips it twice
            }
            .padding(.horizontal, 16)
            .frame(height: 50)
            .contentShape(Rectangle())
            .onTapGesture { setNotifications(!notificationsOn) }   // the whole row flips it, not only the switch
            .accessibilityElement(children: .combine)
            HairlineSeparator()
            Menu {
                Button("Anyone") { setVisibility("anyone") }
                Button("Friends only") { setVisibility("friends") }
            } label: {
                HStack(spacing: 10) {
                    Text("Who can see my hits")
                        .font(CourtlyFont.body)
                        .foregroundStyle(CourtlyColor.ink)
                    Spacer(minLength: 12)
                    Text(profile.hitVisibility == "friends" ? "Friends only" : "Anyone")
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(CourtlyColor.secondary)
                    ChevronMark()
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            HairlineSeparator()
            SettingsRow(title: "Blocked players", value: String(profile.blockedCount)) { navigate(.blockedPlayers) }
        }

        group(label: "Help") {
            SettingsRow(title: "Contact support") { contactSupport() }
            HairlineSeparator()
            SettingsRow(title: "Privacy Policy") { UIApplication.shared.open(AppConfig.privacyURL) }
            HairlineSeparator()
            SettingsRow(title: "Terms of Service") { UIApplication.shared.open(AppConfig.termsURL) }
        }

        group {
            SettingsRow(title: isSigningOut ? "Signing out…" : "Sign out", showsChevron: false) { signOut() }
            HairlineSeparator()
            SettingsRow(title: "Delete account", titleColor: CourtlyColor.red, showsChevron: false) { showsDeleteAlert = true }
        }

        Text("Courtly \(Self.version)")
            .font(CourtlyFont.caption)
            .foregroundStyle(CourtlyColor.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 16)
    }

    /// One card of rows, with a small grey label above it when it has one.
    @ViewBuilder
    private func group<Rows: View>(label: String? = nil, @ViewBuilder rows: () -> Rows) -> some View {
        let built = rows()
        if let label {
            Text(label)
                .font(CourtlyFont.captionSemibold)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 22)
                .padding(.bottom, 8)
        }
        Card {
            VStack(spacing: 0) { built }
        }
        .padding(.top, label == nil ? 16 : 0)
    }

    private func areaValue(_ profile: Profile) -> String {
        guard let label = profile.areaLabel?.components(separatedBy: ",").first else { return "Not set" }
        return "\(label) · \(profile.radius.title)"
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: - Notifications

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOn = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// First time: the system prompt. After that the switch lives in Settings, so open Courtly’s page there.
    private func setNotifications(_ on: Bool) {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if on && settings.authorizationStatus == .notDetermined {
                notificationsOn = await NotificationPermission.request()
            } else if let url = URL(string: UIApplication.openNotificationSettingsURLString) {   // straight to Courtly’s notification settings
                _ = await UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Account

    /// Choices save one after another, so a slower earlier save can never land after a later one, and
    /// each save belongs to the account that chose it: a sign-out while one waits drops it.
    private func setVisibility(_ value: String) {
        let account = session.profile?.id
        let previous = visibilitySave
        visibilitySave = Task { @MainActor in
            await previous?.value
            guard account != nil, session.profile?.id == account else { return }
            do {
                try await session.updateProfile(["hit_visibility": value])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Opens Mail; with no mail account set up, shows the address and copies it instead of doing nothing.
    private func contactSupport() {
        guard let url = URL(string: "mailto:\(AppConfig.supportEmail)") else { return }
        UIApplication.shared.open(url) { opened in
            if !opened {
                UIPasteboard.general.string = AppConfig.supportEmail
                supportCopied = true
            }
        }
    }

    private func signOut() {
        isSigningOut = true
        Task { @MainActor in
            await session.signOut()
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task { @MainActor in
            do {
                try await session.deleteAccount()
            } catch {
                isDeleting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
