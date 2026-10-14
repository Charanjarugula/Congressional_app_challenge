import SwiftUI

/// 03 · Your name. Two fields in one grouped box; first name gets focus.
struct NameView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    private enum Field {
        case first, last
    }

    @FocusState private var focusedField: Field?

    private var canContinue: Bool {
        !draft.trimmedFirstName.isEmpty
    }

    var body: some View {
        OnboardingStepView(
            progress: 0.2,
            title: "What’s your name?",
            subtitle: "This is how your friends will find you."
        ) {
            VStack(spacing: 0) {
                nameField("First name", text: $draft.firstName, field: .first, contentType: .givenName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .last }
                HairlineSeparator()
                nameField("Last name", text: $draft.lastName, field: .last, contentType: .familyName)
                    .submitLabel(.done)
                    .onSubmit { if canContinue { onContinue() } }
            }
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(CourtlyColor.groupedBackground)
            )
            .padding(.top, 28)
        } footer: {
            PrimaryButton(title: "Continue", isEnabled: canContinue, action: onContinue)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            if focusedField == nil { focusedField = .first }
        }
    }

    private func nameField(
        _ placeholder: String,
        text: Binding<String>,
        field: Field,
        contentType: UITextContentType
    ) -> some View {
        TextField(placeholder, text: text)
            .font(CourtlyFont.bodySemibold)
            .foregroundStyle(CourtlyColor.ink)
            .textContentType(contentType)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .padding(.horizontal, 18)
            .frame(height: CourtlyMetrics.fieldHeight)
    }
}
