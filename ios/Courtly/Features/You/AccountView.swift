import SwiftUI
import UIKit

/// Sign-in details, privacy settings, policies, sign out and account deletion.
struct AccountView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.navigate) private var navigate
    @State private var email: String?
    @State private var provider: String?
    @State private var showsPhone = false
    @State private var showsDeleteAlert = false
    @State private var isDeleting = false
    @State private var isSigningOut = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let profile = session.profile {
                    SectionHeader(title: "Sign in", top: 8)
                    Card {
                        VStack(spacing: 0) {
                            ValueRow(title: "Email", value: email ?? "—")
                            HairlineSeparator()
                            SettingsRow(
                                title: "Phone",
                                value: profile.phoneE164.map(Self.formatPhone) ?? "Add",
                                valueColor: profile.phoneE164 == nil ? CourtlyColor.blue : CourtlyColor.secondary
                            ) { showsPhone = true }
                            HairlineSeparator()
                            ValueRow(title: "Signed in with", value: providerTitle)
                        }
                    }

                    SectionHeader(title: "Privacy", top: 24)
                    Card {
                        VStack(spacing: 0) {
                            Menu {
                                Button("Anyone") { setVisibility("anyone") }
                                Button("Friends only") { setVisibility("friends") }
                            } label: {
                                HStack(spacing: 10) {
                                    Text("Who can see my hits")
                                        .font(CourtlyFont.body)
                                        .foregroundStyle(CourtlyColor.ink)
                                    Spacer(minLength: 12)
                                    Text(profile.hitVisibility == "friends" ? "Friends only" : "Anyone")
                                        .font(CourtlyFont.secondary)
                                        .foregroundStyle(CourtlyColor.secondary)
                                    ChevronMark()
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                                .contentShape(Rectangle())
                            }
                            HairlineSeparator()
                            SettingsRow(title: "Blocked players", value: String(profile.blockedCount)) { navigate(.blockedPlayers) }
                            HairlineSeparator()
                            SettingsRow(title: "Privacy Policy") { UIApplication.shared.open(AppConfig.privacyURL) }
                            HairlineSeparator()
                            SettingsRow(title: "Terms of Service") { UIApplication.shared.open(AppConfig.termsURL) }
                            HairlineSeparator()
                            SettingsRow(title: "Contact support") {
                                if let url = URL(string: "mailto:\(AppConfig.supportEmail)") { UIApplication.shared.open(url) }
                            }
                        }
                    }

                    Card {
                        VStack(spacing: 0) {
                            SettingsRow(title: isSigningOut ? "Signing out…" : "Sign out", showsChevron: false) { signOut() }
                            HairlineSeparator()
                            SettingsRow(title: "Delete account", titleColor: CourtlyColor.red, showsChevron: false) { showsDeleteAlert = true }
                        }
                    }
                    .padding(.top, 24)

                    Text("Courtly \(Self.version)")
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                        .padding(.top, 12)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .task {
            let current = await session.currentSession()
            email = current?.email
            provider = current?.provider
        }
        .alert("Delete Account?", isPresented: $showsDeleteAlert) {
            Button("Delete", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your profile, photo, friendships, direct messages and sign-in are deleted right away. Messages you sent in group or hit chats stay for the other players, without your name. This can’t be undone.")
        }
        .sheet(isPresented: $showsPhone) { PhoneSheet() }
        .overlay {
            if isDeleting {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Deleting…")
                        .padding(24)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                }
            }
        }
        .errorAlert($errorMessage)
    }

    private var providerTitle: String {
        switch provider {
        case "apple": "Apple"
        case "google": "Google"
        case "email": "Email"
        default: "—"
        }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// "+15615550142" → "(561) 555-0142"; anything else is shown as typed.
    static func formatPhone(_ e164: String) -> String {
        let digits = e164.filter(\.isNumber)
        guard digits.count == 11, digits.hasPrefix("1") else { return e164 }
        let area = digits.dropFirst().prefix(3)
        let middle = digits.dropFirst(4).prefix(3)
        let last = digits.suffix(4)
        return "(\(area)) \(middle)-\(last)"
    }

    // MARK: - Actions

    private func setVisibility(_ value: String) {
        Task { @MainActor in
            do {
                try await session.updateProfile(["hit_visibility": value])
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func signOut() {
        isSigningOut = true
        Task { @MainActor in
            await session.signOut()
        }
    }

    private func deleteAccount() {
        isDeleting = true
        Task { @MainActor in
            do {
                try await session.deleteAccount()
            } catch {
                isDeleting = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

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
            FieldBox {
                TextField("(561) 555-0142", text: $phone)
                    .font(CourtlyFont.body)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            Text("Friends who have your number can find you. Only a hashed version is stored.")
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
                phone = AccountView.formatPhone(existing)
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
}
