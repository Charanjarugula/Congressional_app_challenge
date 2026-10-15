import SwiftUI
import UIKit
import UserNotifications

/// Your profile, how you play, and what's connected.
struct YouView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    @Environment(\.scenePhase) private var scenePhase
    @State private var sheet: ProfileSheet?
    @State private var notificationsOn = false

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
        .safeAreaInset(edge: .top, spacing: 0) { TabHeader(title: "You", art: .you) }
        .refreshable { await session.refreshProfile() }
        .sheet(item: $sheet) { which in
            switch which {
            case .editProfile: EditProfileSheet()
            case .availability: AvailabilitySheet()
            case .level: LevelSheet()
            case .formats: FormatsSheet()
            case .area: AreaSheet()
            }
        }
        .task { await refreshNotificationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshNotificationStatus() }
            }
        }
    }

    @ViewBuilder
    private func content(_ profile: Profile) -> some View {
        HStack(spacing: 16) {
            PlayerAvatar(card: profile.card, size: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.6)
                    .foregroundStyle(CourtlyColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.top, 20)

        Button {
            sheet = .editProfile
        } label: {
            Text("Edit profile")
                .font(CourtlyFont.secondarySemibold)
                .foregroundStyle(CourtlyColor.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CourtlyColor.card))
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.top, 16)

        SectionHeader(title: "Playing", top: 24)
        Card {
            VStack(spacing: 0) {
                SettingsRow(title: "Level", value: profile.level?.title ?? "Not set") { sheet = .level }
                HairlineSeparator()
                SettingsRow(title: "Plays", value: profile.formats.isEmpty ? "Not set" : profile.formats.map(\.shortTitle).joined(separator: ", ")) { sheet = .formats }
                HairlineSeparator()
                SettingsRow(title: "Area", value: areaValue(profile)) { sheet = .area }
                HairlineSeparator()
                SettingsRow(title: "Availability", value: profile.availability.isEmpty ? "Not set" : nil) { sheet = .availability }
            }
        }

        SectionHeader(title: "Settings", top: 24)
        Card {
            VStack(spacing: 0) {
                HStack {
                    Text("Notifications")
                        .font(CourtlyFont.body)
                        .foregroundStyle(CourtlyColor.ink)
                    Spacer()
                    Toggle("Notifications", isOn: Binding(get: { notificationsOn }, set: { setNotifications($0) }))
                        .labelsHidden()
                        .tint(CourtlyColor.green)
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                HairlineSeparator()
                SettingsRow(title: "Account") { navigate(.account) }
            }
        }
    }

    private func areaValue(_ profile: Profile) -> String {
        guard let label = profile.areaLabel?.components(separatedBy: ",").first else { return "Not set" }
        return "\(label) · \(profile.radius.title)"
    }

    // MARK: - Notifications

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsOn = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// First time: the system prompt. After that the switch lives in Settings, so open it.
    private func setNotifications(_ on: Bool) {
        Task { @MainActor in
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            if on && settings.authorizationStatus == .notDetermined {
                notificationsOn = await NotificationPermission.request()
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                _ = await UIApplication.shared.open(url)
            }
        }
    }
}
