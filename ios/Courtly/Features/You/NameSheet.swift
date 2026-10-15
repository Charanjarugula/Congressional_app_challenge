import SwiftUI

/// First and last name. Others see the first name and last initial.
struct NameSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var seeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        SheetScaffold(title: "Name", canSave: canSave, isSaving: isSaving, onSave: save) {
            SectionLabel(title: "First name")
                .padding(.bottom, 8)
            FieldBox(fill: CourtlyColor.card) {
                TextField("First name", text: $firstName)
                    .font(CourtlyFont.body)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
            }
            SectionLabel(title: "Last name")
                .padding(.top, 16)
                .padding(.bottom, 8)
            FieldBox(fill: CourtlyColor.card) {
                TextField("Last name", text: $lastName)
                    .font(CourtlyFont.body)
                    .textContentType(.familyName)
                    .autocorrectionDisabled()
            }
            Text("Others see your first name and last initial.")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 10)
                .padding(.horizontal, 4)
        }
        .onAppear {
            guard !seeded, let profile = session.profile else { return }
            seeded = true
            firstName = profile.firstName
            lastName = profile.lastName
        }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile([
                    "first_name": firstName.trimmingCharacters(in: .whitespaces),
                    "last_name": lastName.trimmingCharacters(in: .whitespaces),
                ])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
