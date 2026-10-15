import SwiftUI

/// 02 · Create account. Google and Apple first, then email.
struct CreateAccountView: View {
    enum Busy {
        case apple, google, email
    }

    let mode: AccountMode
    /// Runs after the session exists; the button keeps spinning until it returns.
    let onSignedIn: (PersonNameComponents?) async -> Void
    let onEmailSent: (String) -> Void

    @State private var email = ""
    @State private var busy: Busy?
    @State private var errorMessage: String?

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#, options: .regularExpression) != nil
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var body: some View {
        OnboardingStepView(progress: 0.1, title: mode == .signUp ? "Create your account" : "Welcome back") {
            VStack(spacing: 12) {
                SocialSignInButton(kind: .google, isLoading: busy == .google) {
                    run(.google) { try await AppEnvironment.auth.signInWithGoogle(); await onSignedIn(nil) }
                }
                SocialSignInButton(kind: .apple, isLoading: busy == .apple) {
                    run(.apple) { let name = try await AppEnvironment.auth.signInWithApple(); await onSignedIn(name) }
                }
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

            PrimaryButton(title: "Continue", isEnabled: isValidEmail, isLoading: busy == .email, action: continueWithEmail)
                .padding(.top, 16)

            if let errorMessage {
                ErrorCaption(text: errorMessage)
                    .padding(.top, 12)
            }

            termsText
                .padding(.top, 20)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
        }
    }

    /// The two names are real links to the pages, opened in Safari.
    private var termsText: some View {
        Text(termsMarkdown)
            .font(CourtlyFont.caption)
            .foregroundStyle(CourtlyColor.secondary)
            .tint(CourtlyColor.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
    }

    private var termsMarkdown: AttributedString {
        var text = (try? AttributedString(markdown: "By continuing, you are agreeing to our [Terms of Service](\(AppConfig.termsURL.absoluteString)) and [Privacy Policy](\(AppConfig.privacyURL.absoluteString)).")) ?? AttributedString("By continuing, you are agreeing to our Terms of Service and Privacy Policy.")
        for run in text.runs where run.link != nil {
            text[run.range].font = CourtlyFont.captionSemibold
            text[run.range].underlineStyle = .single
            text[run.range].foregroundColor = CourtlyColor.ink
        }
        return text
    }

    private func continueWithEmail() {
        guard isValidEmail else { return }
        let address = normalizedEmail
        run(.email) {
            try await AppEnvironment.auth.sendEmailCode(to: address)
            onEmailSent(address)
        }
    }

    private func run(_ kind: Busy, _ work: @escaping () async throws -> Void) {
        guard busy == nil else { return }
        busy = kind
        errorMessage = nil
        Task { @MainActor in
            do {
                try await work()
            } catch AuthError.cancelled {
                // The player closed the sheet; nothing to say.
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = nil
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
