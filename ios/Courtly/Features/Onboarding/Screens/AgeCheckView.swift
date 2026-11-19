import SwiftUI

/// Shown only where the law has Apple confirm a person's age range (Declared Age Range) and Apple
/// didn't confirm 18+. Courtly never asks for a date of birth; everywhere else this screen never appears.
struct AgeCheckView: View {
    let onContinue: () -> Void

    @State private var result: AgeAssurance.Result
    @State private var isChecking = false

    init(result: AgeAssurance.Result, onContinue: @escaping () -> Void) {
        _result = State(initialValue: result)
        self.onContinue = onContinue
    }

    var body: some View {
        if result == .minor {
            stopped(
                title: "Courtly is for players 18 and over",
                detail: "Your Apple Account shows you’re under \(AgeAssurance.minimumAge), so you can’t use Courtly. You can delete this account now."
            ) {
                LeaveSignUpButton(title: "Delete this account")
            }
        } else {
            stopped(
                title: "Confirm your age to continue",
                detail: "Where you live, apps confirm your age range with Apple. Courtly only learns whether you’re 18 or older."
            ) {
                VStack(spacing: 4) {
                    PrimaryButton(title: "Try again", style: .lime, compact: true, isLoading: isChecking) { Task { await checkAgain() } }
                    LeaveSignUpButton(title: "Delete this account")
                }
            }
        }
    }

    @MainActor
    private func checkAgain() async {
        guard !isChecking else { return }
        isChecking = true
        let fresh = await AgeAssurance.check()
        isChecking = false
        if fresh.letsThrough { onContinue() } else { result = fresh }
    }

    private func stopped<Footer: View>(title: String, detail: String, @ViewBuilder footer: @escaping () -> Footer) -> some View {
        OnboardingStepView(progress: 0.3, title: title, subtitle: detail, appearance: .courtsideBlue) {
            EmptyView()
        } footer: {
            footer()
        }
    }
}
