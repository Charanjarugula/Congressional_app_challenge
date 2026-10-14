import SwiftUI

/// 15 · Notifications pre-prompt. Only "Turn on notifications" triggers the system prompt (16).
struct NotificationsView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var isRequesting = false

    var body: some View {
        OnboardingStepView(
            progress: 1.0,
            title: "Know when they say yes.",
            subtitle: "We’ll let you know when someone wants to hit."
        ) {
            VStack(spacing: 10) {
                NotificationPreviewCard(
                    title: "Jordan accepted",
                    time: "now",
                    message: "Thu 6:30 PM at Wellington Tennis Center. Tap to confirm.",
                    isPrimary: true
                )
                NotificationPreviewCard(
                    title: "Hit tomorrow",
                    time: "5:30 PM",
                    message: "Reminder: Daniel K. · Sat 8:00 AM · Okeeheelee Park",
                    isPrimary: false
                )
            }
            .padding(.top, 40)
            .accessibilityHidden(true)
        } footer: {
            VStack(spacing: 4) {
                PrimaryButton(title: "Turn on notifications", isLoading: isRequesting, action: turnOn)
                TextActionButton(title: "Not now") {
                    draft.notificationsEnabled = false
                    onContinue()
                }
            }
        }
    }

    private func turnOn() {
        guard !isRequesting else { return }
        isRequesting = true
        Task { @MainActor in
            draft.notificationsEnabled = await NotificationPermission.request()
            isRequesting = false
            onContinue()
        }
    }
}

/// Mock iOS notification banner used on the pre-prompt screen.
struct NotificationPreviewCard: View {
    let title: String
    let time: String
    let message: String
    let isPrimary: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(CourtlyColor.blue)
                Circle()
                    .fill(CourtlyColor.lime)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    Spacer()
                    Text(time)
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                }
                Text(message)
                    .font(CourtlyFont.secondary)
                    .lineSpacing(2)
                    .foregroundStyle(CourtlyColor.ink)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CourtlyColor.groupedBackground)
                .shadow(color: isPrimary ? CourtlyColor.ink.opacity(0.08) : .clear, radius: 12, y: 8)
        )
        .opacity(isPrimary ? 1 : 0.55)
    }
}
