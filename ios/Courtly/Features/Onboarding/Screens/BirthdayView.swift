import SwiftUI

/// 04 · Birthday. First, where the law requires it, Apple's age range check (Declared Age Range):
/// under 18 stops here. Then the wheel picker; Continue is held until the player meets the minimum age.
struct BirthdayView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var ageCheck: AgeAssurance.Result?
    @State private var isChecking = false

    init(draft: OnboardingDraft, onContinue: @escaping () -> Void) {
        self.draft = draft
        self.onContinue = onContinue
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Layout tests exercise the birthday gate without depending on Apple's account/region service.
    init(previewDraft: OnboardingDraft, onContinue: @escaping () -> Void) {
        self.draft = previewDraft
        self.onContinue = onContinue
        _ageCheck = State(initialValue: .useBirthdayGate)
    }
    #endif

    private var allowedRange: ClosedRange<Date> {
        let earliest = Calendar.current.date(byAdding: .year, value: -100, to: .now) ?? .distantPast
        return earliest...Date.now
    }

    var body: some View {
        Group {
            switch ageCheck {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .tint(.white)
                    .background(CourtlyColor.blue.ignoresSafeArea())
            case .minor?:
                stopped(
                    title: "Courtly is for players 18 and over",
                    detail: "Your Apple Account shows you’re under \(OnboardingDraft.minimumAge), so you can’t use Courtly. You can delete this account now."
                ) {
                    LeaveSignUpButton(title: "Delete this account")
                }
            case .mustConfirm?:
                stopped(
                    title: "Confirm your age to continue",
                    detail: "Where you live, apps confirm your age range with Apple. Courtly only learns whether you’re 18 or older."
                ) {
                    VStack(spacing: 4) {
                        PrimaryButton(title: "Try again", style: .lime, compact: true, isLoading: isChecking) { Task { await runCheck() } }
                        LeaveSignUpButton(title: "Delete this account")
                    }
                }
            case .adult?, .useBirthdayGate?:
                birthdayStep
            }
        }
        .task { if ageCheck == nil { await runCheck() } }
    }

    @MainActor
    private func runCheck() async {
        guard !isChecking else { return }
        isChecking = true
        ageCheck = await AgeAssurance.check()
        isChecking = false
    }

    private func stopped<Footer: View>(title: String, detail: String, @ViewBuilder footer: @escaping () -> Footer) -> some View {
        OnboardingStepView(progress: 0.3, title: title, subtitle: detail, appearance: .courtsideBlue) {
            EmptyView()
        } footer: {
            footer()
        }
    }

    private var birthdayStep: some View {
        OnboardingStepView(
            progress: 0.3,
            title: "When’s your birthday?",
            subtitle: "Only used to confirm you’re 18 or older. Other players never see it.",
            appearance: .courtsideBlue
        ) {
            DatePicker("Birthday", selection: $draft.birthday, in: allowedRange, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .onChange(of: draft.birthday) { _, _ in draft.birthdayChosen = true }
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .frame(height: 216)
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
                .environment(\.colorScheme, .light)
                .padding(.top, 24)

            if !draft.birthdayChosen {
                Text("Scroll to your birthday.")
                    .font(CourtlyFont.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            } else if !draft.meetsMinimumAge {
                OnboardingErrorCaption(text: "Courtly is for players \(OnboardingDraft.minimumAge) and over.")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        } footer: {
            VStack(spacing: 4) {
                PrimaryButton(title: "Continue", style: .lime, compact: true, isEnabled: draft.birthdayChosen && draft.meetsMinimumAge, action: onContinue)
                if draft.birthdayChosen && !draft.meetsMinimumAge {
                    LeaveSignUpButton(title: "Delete this account")
                }
            }
        }
    }
}
