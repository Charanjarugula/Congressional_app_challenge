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
            subtitle: "This is how your friends will find you.",
            appearance: .courtsideBlue
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("First name").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                nameField("First name", text: $draft.firstName, field: .first, contentType: .givenName)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .last }
                Text("Last name").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                nameField("Last name", text: $draft.lastName, field: .last, contentType: .familyName)
                    .submitLabel(.done)
                    .onSubmit { if canContinue { onContinue() } }
            }
            .padding(.top, 24)
        } footer: {
            PrimaryButton(title: "Continue", style: .lime, compact: true, isEnabled: canContinue, action: onContinue)
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
        TextField(placeholder, text: text, prompt: Text(placeholder).foregroundStyle(CourtlyColor.secondary))
            .font(CourtlyFont.bodySemibold)
            .foregroundStyle(CourtlyColor.ink)
            .textContentType(contentType)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .focused($focusedField, equals: field)
            .padding(.horizontal, 18)
            .frame(height: CourtlyMetrics.fieldHeight)
            .background(.white, in: RoundedRectangle(cornerRadius: 16))
    }
}
