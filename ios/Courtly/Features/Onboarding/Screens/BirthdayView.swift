import SwiftUI

/// 04 · Birthday. Wheel picker; Continue is held until the player meets the minimum age.
struct BirthdayView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    private var allowedRange: ClosedRange<Date> {
        let earliest = Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        return earliest...Date.now
    }

    var body: some View {
        OnboardingStepView(
            progress: 0.3,
            title: "When’s your birthday?",
            subtitle: "We’ll use this to match you with players around your age.",
            scrolls: false
        ) {
            DatePicker("Birthday", selection: $draft.birthday, in: allowedRange, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 216)
                .padding(.top, 32)

            if !draft.meetsMinimumAge {
                Text("Courtly is for players \(OnboardingDraft.minimumAge) and over.")
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.red)
                    .padding(.top, 12)
            }
        } footer: {
            PrimaryButton(title: "Continue", isEnabled: draft.meetsMinimumAge, action: onContinue)
        }
    }
}
