import SwiftUI

/// "Delete this account" for someone who signed in but won't or can't finish sign-up. The account
/// already exists at this point, so App Review expects a way to remove it from inside the app.
struct LeaveSignUpButton: View {
    var title = "Changed your mind? Delete this account"
    @Environment(AppSession.self) private var session
    @State private var confirming = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    var body: some View {
        TextActionButton(title: isDeleting ? "Deleting…" : title, color: .white) { confirming = true }
            .disabled(isDeleting)
            .alert("Delete this account?", isPresented: $confirming) {
                Button("Delete", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Everything you’ve entered so far and your sign-in are removed. This can’t be undone.")
            }
            .errorAlert($errorMessage, title: "Couldn’t delete the account")
    }

    private func delete() {
        isDeleting = true
        Task { @MainActor in
            do {
                try await session.deleteAccount(unfinished: true)
            } catch {
                errorMessage = error.localizedDescription
            }
            isDeleting = false
        }
    }
}
