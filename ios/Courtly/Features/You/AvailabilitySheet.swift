import SwiftUI

struct AvailabilitySheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var mask = AvailabilityMask()
    @State private var blocked = AvailabilityMask()
    @State private var busy = AvailabilityMask()
    @State private var provider: CalendarProvider = .none
    @State private var seeded = false
    @State private var isConnecting = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var calendarService = CalendarService()

    var body: some View {
        SheetScaffold(title: "Availability", isSaving: isSaving, detents: [.large], onSave: save) {
            Text("Tap once when you’re free, twice when you’re busy.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 16)
            AvailabilityGrid(selected: $mask, busy: busy, blocked: $blocked)
            legend
                .padding(.top, 14)
                .padding(.horizontal, 4)
            Text("Hits during busy times stay out of your feed.")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 4)

            SectionHeader(title: "Calendar", top: 28)
            Card {
                HStack(spacing: 14) {
                    CalendarIcon(size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Apple Calendar")
                            .font(CourtlyFont.body)
                            .foregroundStyle(CourtlyColor.ink)
                        Text(provider == .none ? "Marks times you have events as busy" : "Busy times come from your events")
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                    Spacer(minLength: 8)
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Toggle("Apple Calendar", isOn: Binding(get: { provider != .none }, set: { $0 ? connect() : disconnect() }))
                            .labelsHidden()
                            .tint(CourtlyColor.green)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
            }
        }
        .onAppear {
            guard !seeded, let profile = session.profile else { return }
            seeded = true
            mask = profile.availability
            blocked = profile.busy
            busy = profile.busyThisWeek
            provider = profile.calendarProvider
        }
        .errorAlert($errorMessage)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CourtlyColor.blue)
                    .frame(width: 12, height: 12)
                Text("Free")
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
        .foregroundStyle(CourtlyColor.secondary)
    }

    private func connect() {
        isConnecting = true
        Task { @MainActor in
            do {
                let result = try await calendarService.connect()
                provider = result.connection.provider
                busy = result.busy
            } catch {
                errorMessage = "Calendar access is off for Courtly. You can turn it on in Settings."
            }
            isConnecting = false
        }
    }

    private func disconnect() {
        provider = .none
        busy = AvailabilityMask()
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile([
                    "availability_mask": Int(mask.rawValue),
                    "busy_mask": Int(blocked.rawValue),
                    "busy_mask_week": Int(busy.rawValue),
                    "calendar_provider": provider.rawValue,
                ])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
