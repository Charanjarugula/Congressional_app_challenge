import SwiftUI

/// 02b · Email code. The six-digit code from the email (the App Review account types its eight-digit
/// password here instead); the same step for new and returning players.
struct EmailCodeView: View {
    let email: String
    /// Runs after the session exists; the button keeps spinning until it returns.
    let onSignedIn: () async -> Void

    @State private var code = ""
    @State private var isVerifying = false
    @State private var isResending = false
    @State private var message: String?
    @State private var messageIsError = false
    @FocusState private var isFocused: Bool

    private var digits: String { code.filter(\.isNumber) }
    private var canContinue: Bool { (6...8).contains(digits.count) }

    var body: some View {
        OnboardingStepView(
            progress: 0.1,
            title: "Check your email",
            subtitle: "We sent a code to \(email).",
            scrolls: false
        ) {
            FieldBox {
                TextField("Code", text: $code)
                    .font(CourtlyFont.rounded(28, weight: .bold))
                    .foregroundStyle(CourtlyColor.ink)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .focused($isFocused)
                    .onChange(of: code) { _, newValue in
                        let trimmed = String(newValue.filter(\.isNumber).prefix(8))
                        if trimmed != newValue { code = trimmed }
                        if trimmed.count == 8 { verify() }
                    }
            }
            .padding(.top, 28)

            if let message {
                Text(message)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(messageIsError ? CourtlyColor.red : CourtlyColor.secondary)
                    .padding(.top, 10)
            }

            Button(action: resend) {
                Text(isResending ? "Sending…" : "Resend code")
                    .font(CourtlyFont.secondarySemibold)
                    .foregroundStyle(CourtlyColor.blue)
            }
            .buttonStyle(.plain)
            .disabled(isResending)
            .padding(.top, 20)
        } footer: {
            PrimaryButton(title: "Continue", isEnabled: canContinue, isLoading: isVerifying, action: verify)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(400))
            isFocused = true
        }
    }

    private func verify() {
        guard canContinue, !isVerifying else { return }
        isVerifying = true
        message = nil
        Task { @MainActor in
            do {
                try await AppEnvironment.auth.verifyEmailCode(email: email, code: digits)
                await onSignedIn()
                isVerifying = false
            } catch {
                isVerifying = false
                messageIsError = true
                message = error.localizedDescription
            }
        }
    }

    private func resend() {
        guard !isResending else { return }
        isResending = true
        Task { @MainActor in
            do {
                try await AppEnvironment.auth.sendEmailCode(to: email)
                messageIsError = false
                message = "Sent a new code."
            } catch {
                messageIsError = true
                message = error.localizedDescription
            }
            isResending = false
        }
    }
}
