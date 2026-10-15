import SwiftUI

/// Add or change the phone number friends can find you by.
struct PhoneSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var normalized: String? { ContactsService.normalizePhone(phone) }

    var body: some View {
        SheetScaffold(title: "Phone", canSave: normalized != nil, isSaving: isSaving, onSave: save) {
            SectionLabel(title: "Mobile number")
                .padding(.bottom, 8)
            FieldBox(fill: CourtlyColor.card) {
                TextField("(561) 555-0142", text: $phone)
                    .font(CourtlyFont.body)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            Text("Optional. Stored with your profile and never shown to other players.")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 10)
                .padding(.horizontal, 4)
            if session.profile?.phoneE164 != nil {
                TextActionButton(title: "Remove number", color: CourtlyColor.red) { remove() }
                    .padding(.top, 8)
            }
        }
        .onAppear {
            if phone.isEmpty, let existing = session.profile?.phoneE164 {
                phone = PhoneSheet.format(existing)
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func save() {
        guard let normalized else { return }
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile(["phone_e164": normalized])   // the server hashes it for contact matching
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func remove() {
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile(["phone_e164": NSNull()])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    /// "+15615550142" → "(561) 555-0142"; anything else is shown as typed.
    static func format(_ e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        guard digits.count == 11, digits.hasPrefix("1") else { return e164 }
        let area = digits.dropFirst().prefix(3)
        let middle = digits.dropFirst(4).prefix(3)
        let last = digits.suffix(4)
        return "(\(area)) \(middle)-\(last)"
    }
}
