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

    private var isBlue: Bool { true }
    private var labelColor: Color { isBlue ? .white : CourtlyColor.ink }
    private var supportingColor: Color { isBlue ? .white.opacity(0.85) : CourtlyColor.secondary }

    private var isValidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]{2,}$"#, options: .regularExpression) != nil
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var body: some View {
        OnboardingStepView(progress: 0.1, title: mode == .signUp ? "Create your account" : "Welcome back", appearance: .courtsideBlue) {
            VStack(spacing: 8) {
                SocialSignInButton(kind: .google, isLoading: busy == .google) {
                    run(.google) { try await AppEnvironment.auth.signInWithGoogle(); await onSignedIn(nil) }
                }
                SocialSignInButton(kind: .apple, isLoading: busy == .apple) {
                    run(.apple) { let name = try await AppEnvironment.auth.signInWithApple(); await onSignedIn(name) }
                }
            }
            .padding(.top, 24)

            Text("or use email")
                .font(CourtlyFont.caption)
                .foregroundStyle(supportingColor)
                .padding(.vertical, 16)

            Text("Email")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(labelColor)

            FieldBox(fill: .white, cornerRadius: 16, horizontalPadding: 16) {
                TextField("Email", text: $email, prompt: Text(verbatim: "you@example.com").foregroundStyle(CourtlyColor.secondary))
                    .accessibilityLabel("Email")
                    .font(CourtlyFont.body)
                    .foregroundStyle(CourtlyColor.ink)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit(continueWithEmail)
            }
            .padding(.top, 16)

            if let errorMessage {
                ErrorCaption(text: errorMessage)
                    .padding(isBlue ? 12 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(isBlue ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
            }

            termsText
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            PrimaryButton(title: "Continue", style: .lime, compact: true,
                          isEnabled: isValidEmail, isLoading: busy == .email, action: continueWithEmail)
        }
    }

    /// The two names are real links to the pages, opened in Safari.
    private var termsText: some View {
        Text(termsMarkdown)
            .font(CourtlyFont.caption)
            .foregroundStyle(supportingColor)
            .tint(labelColor)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
    }

    private var termsMarkdown: AttributedString {
        var text = (try? AttributedString(markdown: "By continuing, you are agreeing to our [Terms of Service](\(AppConfig.termsURL.absoluteString)) and [Privacy Policy](\(AppConfig.privacyURL.absoluteString)).")) ?? AttributedString("By continuing, you are agreeing to our Terms of Service and Privacy Policy.")
        for run in text.runs where run.link != nil {
            text[run.range].font = CourtlyFont.captionSemibold
            text[run.range].underlineStyle = .single
            text[run.range].foregroundColor = labelColor
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
                errorMessage = AuthError.message(for: error)
            }
            busy = nil
        }
    }
}

/// Provider actions for account entry, retaining their existing marks and authentication callbacks.
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

    private var foreground: Color { kind == .apple ? .white : CourtlyColor.ink }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                mark
                Text(kind.title)
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(foreground)
            }
            .opacity(isLoading ? 0 : 1)
            .overlay {
                if isLoading {
                    ProgressView().tint(foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(kind == .apple ? CourtlyColor.ink : .white)
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
                .foregroundStyle(foreground)
        }
    }
}
