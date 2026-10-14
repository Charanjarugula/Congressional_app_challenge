import SwiftUI

/// 17 · You're in. Green check, greeting, Let's hit. Saving the profile happens here.
struct YoureInView: View {
    let firstName: String
    let onLetsHit: () async throws -> Void

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var greeting: String {
        firstName.isEmpty ? "You’re in." : "You’re in, \(firstName)."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle().fill(CourtlyColor.green)
                    CheckmarkShape()
                        .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 30, height: 16)
                }
                .frame(width: 72, height: 72)
                Circle()
                    .fill(CourtlyColor.lime)
                    .frame(width: 12, height: 12)
                    .offset(x: 2, y: 4)
            }
            Text(greeting)
                .font(CourtlyFont.largeTitle)
                .tracking(-0.7)
                .foregroundStyle(CourtlyColor.ink)
                .multilineTextAlignment(.center)
                .padding(.top, 28)
            Text("Welcome to Courtly. Time to find someone to play with.")
                .font(CourtlyFont.body)
                .lineSpacing(4)
                .foregroundStyle(CourtlyColor.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
                .padding(.top, 10)
            if let errorMessage {
                ErrorCaption(text: errorMessage)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .padding(.bottom, 70)
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PrimaryButton(title: "Let’s hit", isLoading: isSaving, action: finish)
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.bottom, 16)
                .background(Color.white.ignoresSafeArea())
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func finish() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            do {
                try await onLetsHit()
            } catch {
                isSaving = false
                errorMessage = "Couldn’t save your profile. \(error.localizedDescription)"
            }
        }
    }
}
