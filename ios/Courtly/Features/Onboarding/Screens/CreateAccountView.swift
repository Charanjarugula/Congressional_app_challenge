import SwiftUI

/// 02 · Create account. Google and Apple first, then email.
struct CreateAccountView: View {
    let mode: AccountMode
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var email = ""
    @State private var busyProvider: AuthProvider?
    @State private var errorMessage: String?

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".") && trimmed.count >= 6
    }

    var body: some View {
        OnboardingStepView(progress: 0.1, title: mode == .signUp ? "Create your account" : "Welcome back") {
            VStack(spacing: 12) {
                SocialSignInButton(kind: .google, isLoading: busyProvider == .google) { signIn(.google) }
                SocialSignInButton(kind: .apple, isLoading: busyProvider == .apple) { signIn(.apple) }
            }
            .padding(.top, 32)

            HStack(spacing: 12) {
                HairlineSeparator()
                Text("or")
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
                HairlineSeparator()
            }
            .padding(.vertical, 24)

            Text("Email")
                .font(CourtlyFont.secondarySemibold)
                .foregroundStyle(CourtlyColor.ink)

            FieldBox {
                TextField("Email", text: $email)
                    .font(CourtlyFont.body)
                    .foregroundStyle(CourtlyColor.ink)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit(continueWithEmail)
            }
            .padding(.top, 8)

            PrimaryButton(
                title: "Continue",
                isEnabled: isValidEmail,
                isLoading: busyProvider == .email(email),
                action: continueWithEmail
            )
            .padding(.top, 16)

            if let errorMessage {
                Text(errorMessage)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.red)
                    .padding(.top, 12)
            }

            termsText
                .padding(.top, 20)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
        }
    }

    private var termsText: some View {
        (Text("By continuing, you are agreeing to our ")
            + Text("Terms of Service").fontWeight(.semibold).underline().foregroundStyle(CourtlyColor.ink)
            + Text(" and ")
            + Text("Privacy Policy").fontWeight(.semibold).underline().foregroundStyle(CourtlyColor.ink)
            + Text("."))
            .font(CourtlyFont.caption)
            .foregroundStyle(CourtlyColor.secondary)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }

    private func continueWithEmail() {
        guard isValidEmail else { return }
        signIn(.email(email.trimmingCharacters(in: .whitespaces).lowercased()))
    }

    private func signIn(_ provider: AuthProvider) {
        guard busyProvider == nil else { return }
        busyProvider = provider
        errorMessage = nil
        Task { @MainActor in
            do {
                draft.account = try await AppEnvironment.auth.signIn(with: provider)
                busyProvider = nil
                onContinue()
            } catch {
                busyProvider = nil
                errorMessage = "Couldn’t sign in. Please try again."
            }
        }
    }
}

/// White 52pt button with a 1.5pt border and a provider mark.
struct SocialSignInButton: View {
    enum Kind {
        case google, apple

        var title: String {
            switch self {
            case .google: "Continue with Google"
            case .apple: "Continue with Apple"
            }
        }
    }

    let kind: Kind
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                mark
                Text(kind.title)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
            }
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView().tint(CourtlyColor.ink)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CourtlyMetrics.primaryButtonHeight)
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .strokeBorder(CourtlyColor.separator, lineWidth: 1.5)
            )
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoading)
    }

    @ViewBuilder
    private var mark: some View {
        switch kind {
        case .google:
            ZStack {
                Circle().fill(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: Color(hex: 0x4285F4), location: 0),
                            .init(color: Color(hex: 0x4285F4), location: 0.25),
                            .init(color: Color(hex: 0x34A853), location: 0.25),
                            .init(color: Color(hex: 0x34A853), location: 0.5),
                            .init(color: Color(hex: 0xFBBC05), location: 0.5),
                            .init(color: Color(hex: 0xFBBC05), location: 0.75),
                            .init(color: Color(hex: 0xEA4335), location: 0.75),
                            .init(color: Color(hex: 0xEA4335), location: 1),
                        ]),
                        center: .center
                    )
                )
                Circle().fill(Color.white).frame(width: 12, height: 12)
            }
            .frame(width: 20, height: 20)
        case .apple:
            Image(systemName: "apple.logo")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(CourtlyColor.ink)
        }
    }
}
