import SwiftUI

/// 05 · Gender. Single choice.
struct GenderView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepView(
            progress: 0.4,
            title: "What’s your gender?",
            subtitle: "Some players prefer to hit with men or women. We’ll use this to match you."
        ) {
            VStack(spacing: 8) {
                ForEach(Gender.allCases) { option in
                    ChoiceRow(title: option.title, isSelected: draft.gender == option) {
                        draft.gender = option
                    }
                }
            }
            .padding(.top, 28)
        } footer: {
            PrimaryButton(title: "Continue", isEnabled: draft.gender != nil, action: onContinue)
        }
    }
}

/// 06 · Tennis journey. Single choice with a description per level.
struct LevelView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    var body: some View {
        OnboardingStepView(
            progress: 0.5,
            title: "Where are you in your tennis journey?",
            subtitle: "You can change this anytime."
        ) {
            VStack(spacing: 8) {
                ForEach(PlayerLevel.allCases) { option in
                    ChoiceRow(title: option.title, subtitle: option.description, isSelected: draft.level == option) {
                        draft.level = option
                    }
                }
            }
            .padding(.top, 28)
        } footer: {
            PrimaryButton(title: "Continue", isEnabled: draft.level != nil, action: onContinue)
        }
    }
}

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
