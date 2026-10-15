import SwiftUI

/// 07 · What to play. Multiple choice.
struct FormatsView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepView(
            progress: 0.6,
            title: "What do you want to play?",
            subtitle: "Pick all that apply."
        ) {
            VStack(spacing: 8) {
                ForEach(PlayFormat.allCases) { option in
                    ChoiceRow(title: option.title, subtitle: option.description, isSelected: draft.formats.contains(option)) {
                        if draft.formats.contains(option) {
                            draft.formats.remove(option)
                        } else {
                            draft.formats.insert(option)
                        }
                    }
                }
            }
            .padding(.top, 28)
        } footer: {
            PrimaryButton(title: "Continue", isEnabled: !draft.formats.isEmpty, action: onContinue)
        }
    }
}
