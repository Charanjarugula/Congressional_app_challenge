import SwiftUI
import UIKit

/// 10 · Availability, 11 · Connect calendar (sheet), 12 · Availability synced.
struct AvailabilityView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var showsCalendarSheet = false

    private var subtitle: String {
        draft.calendar == nil
            ? "Tap the blocks that usually work. You can change this anytime."
            : "Blocks you’re already busy are greyed out. Tap to override."
    }

    var body: some View {
        OnboardingStepView(progress: 0.8, title: "When do you usually play?", subtitle: subtitle, appearance: .courtsideBlue) {
            AvailabilityGrid(selected: $draft.availability, busy: draft.busyThisWeek)
                .padding(12)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                .padding(.top, 28)

            if let connection = draft.calendar {
                legend
                    .padding(.top, 12)
                CalendarConnectedRow(connection: connection) { showsCalendarSheet = true }
                    .padding(.top, 28)
            } else {
                CalendarConnectRow { showsCalendarSheet = true }
                    .padding(.top, 28)
            }
        } footer: {
            PrimaryButton(title: "Continue", style: .lime, compact: true, action: onContinue)
        }
        .sheet(isPresented: $showsCalendarSheet) {
            ConnectCalendarSheet(draft: draft)
                .preferredColorScheme(.light)
                .presentationDetents([.height(draft.calendar == nil ? 330 : 300)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CourtlyColor.lime)
                    .frame(width: 12, height: 12)
                Text("Free to play")
            }
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CourtlyColor.groupedBackground)
                    DiagonalStripes(spacing: 4)
                        .stroke(CourtlyColor.alertSeparator, lineWidth: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .frame(width: 12, height: 12)
                Text("Busy")
            }
        }
        .font(CourtlyFont.caption)
        .foregroundStyle(.white.opacity(0.85))
    }
}

/// 7 columns × 3 blocks. Selected blocks are blue with a lime dot; busy blocks are hatched.
struct AvailabilityGrid: View {
    @Binding var selected: AvailabilityMask
    /// Blocks the calendar says are busy this week; shown striped, not editable here.
    var busy = AvailabilityMask()
    /// Blocks the player marks busy by hand. When bound, a tap goes free → busy → clear.
    var blocked: Binding<AvailabilityMask>? = nil

    private let labelWidth: CGFloat = 78

    var body: some View {
        Grid(horizontalSpacing: 5, verticalSpacing: 5) {
            GridRow {
                Color.clear
                    .frame(width: labelWidth, height: 16)
                ForEach(0..<7, id: \.self) { day in
                    Text(AvailabilityMask.dayLetters[day])
                        .font(CourtlyFont.captionSemibold)
                        .foregroundStyle(selected.hasAny(day: day) ? CourtlyColor.blue : CourtlyColor.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(AvailabilityMask.Block.allCases) { block in
                GridRow {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(block.title)
                            .font(CourtlyFont.secondarySemibold)
                            .foregroundStyle(CourtlyColor.ink)
                        Text(block.hoursLabel)
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                    .frame(width: labelWidth, alignment: .leading)
                    ForEach(0..<7, id: \.self) { day in
                        cell(day: day, block: block)
                    }
                }
            }
        }
    }

    private func cell(day: Int, block: AvailabilityMask.Block) -> some View {
        let isOn = selected.contains(day: day, block: block)
        let isBlocked = blocked?.wrappedValue.contains(day: day, block: block) ?? false
        let isBusy = isBlocked || busy.contains(day: day, block: block)
        return Button {
            if let blocked {
                if isOn {
                    selected.toggle(day: day, block: block)
                    blocked.wrappedValue.insert(day: day, block: block)
                } else if isBlocked {
                    blocked.wrappedValue.toggle(day: day, block: block)
                } else {
                    selected.toggle(day: day, block: block)
                }
            } else {
                selected.toggle(day: day, block: block)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? CourtlyColor.blue : CourtlyColor.groupedBackground)
                if isBusy && !isOn {
                    DiagonalStripes(spacing: 8)
                        .stroke(CourtlyColor.separator, lineWidth: 2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if isOn {
                    Circle()
                        .fill(CourtlyColor.lime)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(AvailabilityMask.dayNames[day]) \(block.title)")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Grouped row that opens the connect-calendar sheet.
struct CalendarConnectRow: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CalendarIcon(size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connect your calendar")
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    Text("Skip blocks you’re already busy. Optional.")
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CourtlyColor.secondary)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(.white)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Grouped row shown once a calendar is connected.
struct CalendarConnectedRow: View {
    let connection: CalendarConnection
    let onManage: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            CalendarIcon(size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(connection.provider == .apple ? "Apple Calendar" : "Google Calendar")
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    SuccessBadge(size: 18)
                }
                Text(connection.detail)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
            }
            Spacer(minLength: 8)
            LinkButton(title: "Manage", action: onManage)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                .fill(.white)
        )
    }
}

/// 11 · Connect your calendar. Apple Calendar only in v1; Google waits on OAuth verification.
struct ConnectCalendarSheet: View {
    @Bindable var draft: OnboardingDraft
    @Environment(\.dismiss) private var dismiss

    @State private var isConnecting = false
    @State private var wasDenied = false
    @State private var calendarService = CalendarService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(draft.calendar == nil ? "Connect your calendar" : "Your calendar")
                .font(CourtlyFont.sheetTitle)
                .tracking(-0.4)
                .foregroundStyle(CourtlyColor.ink)
                .padding(.top, 24)
            Text(draft.calendar == nil
                ? "We only read free/busy times to skip blocks you can’t make. Event details stay private."
                : "Busy blocks come from your calendar. Disconnect to stop reading free/busy times.")
                .font(CourtlyFont.secondary)
                .lineSpacing(3)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 6)

            VStack(spacing: 10) {
                if draft.calendar == nil {
                    providerRow(title: "Apple Calendar", isLoading: isConnecting, action: connectApple)
                } else {
                    providerRow(title: "Disconnect Apple Calendar", isLoading: false, action: disconnect)
                }
            }
            .padding(.top, 22)

            if wasDenied {
                HStack(spacing: 4) {
                    Text("Calendar access is off for Courtly.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .foregroundStyle(CourtlyColor.blue)
                }
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 12)
            }

            TextActionButton(title: draft.calendar == nil ? "Close" : "Done") { dismiss() }
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .background(Color.white)
    }

    private func providerRow(title: String, isLoading: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                CalendarIcon(size: 32)
                Text(title)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                Spacer(minLength: 8)
                if isLoading {
                    ProgressView().tint(CourtlyColor.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CourtlyColor.secondary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: CourtlyMetrics.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(CourtlyColor.groupedBackground)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
    }

    private func connectApple() {
        guard !isConnecting else { return }
        isConnecting = true
        wasDenied = false
        Task { @MainActor in
            do {
                let result = try await calendarService.connect()
                draft.calendar = result.connection
                draft.busyThisWeek = result.busy
                isConnecting = false
                dismiss()
            } catch {
                isConnecting = false
                wasDenied = true
            }
        }
    }

    private func disconnect() {
        draft.calendar = nil
        draft.busyThisWeek = AvailabilityMask()
        dismiss()
    }
}
