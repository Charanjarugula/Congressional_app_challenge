import SwiftUI

/// 02b · Email code. The six-digit code from the email (the App Review account types its eight-digit
/// password here instead); the same step for new and returning players.
struct EmailCodeView: View {
    let email: String
    /// Runs after the session exists; the button keeps spinning until it returns.
    let onSignedIn: () async -> Void

    @State private var code = ""
    @State private var isVerifying = false
    @State private var resendAvailableAt = Date.now.addingTimeInterval(60)   // the first code just went out
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
            appearance: .courtsideBlue
        ) {
            Text("Code")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.top, 24)
            FieldBox(fill: .white, cornerRadius: 16, horizontalPadding: 16) {
                TextField("Code", text: $code)
                    .font(CourtlyFont.bodySemibold)
                    .tracking(4)
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
            .padding(.top, 16)

            if let message {
                Text(message)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(messageIsError ? CourtlyColor.red : CourtlyColor.secondary)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 10)
            }

            // A minute between codes, which is also what the server allows; counting down beats an error.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let wait = max(0, Int(resendAvailableAt.timeIntervalSince(context.date).rounded(.up)))
                Button(action: resend) {
                    Text(isResending ? "Sending…" : wait > 0 ? "Resend code in \(wait)s" : "Resend code")
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(CourtlyColor.blue)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(RoundedRectangle(cornerRadius: 16).fill(.white))
                }
                .buttonStyle(.plain)
                .disabled(isResending || wait > 0)
            }
            .padding(.top, 16)
            Text("We sent a code to \(email).")
                .font(CourtlyFont.caption)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
        } footer: {
            PrimaryButton(title: "Continue", style: .lime, compact: true, isEnabled: canContinue, isLoading: isVerifying, action: verify)
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
        guard !isResending, resendAvailableAt <= .now else { return }
        isResending = true
        Task { @MainActor in
            do {
                try await AppEnvironment.auth.sendEmailCode(to: email)
                messageIsError = false
                message = "Sent a new code."
                resendAvailableAt = .now.addingTimeInterval(60)
            } catch {
                messageIsError = true
                message = error.localizedDescription
            }
            isResending = false
        }
    }
}
