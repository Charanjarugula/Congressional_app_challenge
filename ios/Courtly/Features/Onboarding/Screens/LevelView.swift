import SwiftUI

/// 06 · Tennis journey. Single choice with a description per level.
struct LevelView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepView(
            progress: 0.5,
            title: "Where are you in your tennis journey?",
            subtitle: "You can change this anytime.",
            appearance: .courtsideBlue
        ) {
            VStack(spacing: 8) {
                ForEach(PlayerLevel.allCases) { option in
                    ChoiceRow(courtside: true, title: option.title, subtitle: option.description, isSelected: draft.level == option) {
                        draft.level = option
                    }
                }
            }
            .padding(.top, 24)
        } footer: {
            PrimaryButton(title: "Continue", style: .lime, compact: true, isEnabled: draft.level != nil, action: onContinue)
        }
    }
}
