import Foundation
import Observation

struct AppAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

/// App-wide state: whether there is a signed-in, onboarded player, and their profile.
@Observable
final class AppSession {
    enum Stage: Equatable {
        case loading
        case onboarding(resume: Bool)   // resume = signed in but profile not finished
        case main
    }

    private(set) var stage: Stage = .loading
    private(set) var profile: Profile?
    var alert: AppAlert?

    private let client = SupabaseClient.shared

    init() {
        profile = ProfileCache.load()
        Task { @MainActor in await restore() }
    }

    /// On launch: no session → welcome; session + unfinished profile → resume; otherwise the app.
    @MainActor
    func restore() async {
        do {
            _ = try await client.validSession()
            let me = try await API.Profile.me()
            apply(me)
        } catch SupabaseError.notSignedIn {
            profile = nil
            ProfileCache.save(nil)
            stage = .onboarding(resume: false)
        } catch {
            // Offline or backend hiccup: keep going with what the device has.
            if let cached = profile, cached.isOnboarded {
                stage = .main
            } else {
                stage = .onboarding(resume: profile != nil)
            }
        }
    }

    /// After any sign-in: returns true when the player already finished onboarding (now in the app).
    @MainActor
    func handleSignedIn() async throws -> Bool {
        let me = try await API.Profile.me()
        if me.isOnboarded {
            apply(me)
            return true
        }
        profile = me
        return false
    }

    @MainActor
    func completeOnboarding(with draft: OnboardingDraft, accountEmail: String?) async throws {
        let session = try await client.validSession()
        _ = try await API.Profile.update(draft.makePatch(accountEmail: accountEmail ?? session.email))
        let me = try await API.Profile.completeOnboarding()
        apply(me)
    }

    @MainActor
    func refreshProfile() async {
        let owner = profile?.id
        if let me = try? await API.Profile.me(), profile?.id == owner, owner != nil {
            // Only while the same player is still signed in; a late answer after a sign-out stays out.
            profile = me
            ProfileCache.save(me)
        }
    }

    @MainActor
    func signOut() async {
        await client.signOut()
        profile = nil
        ProfileCache.save(nil)
        stage = .onboarding(resume: false)
    }

    @MainActor
    func show(_ error: Error, title: String = "Something went wrong") {
        alert = AppAlert(title: title, message: error.localizedDescription)
    }

    @MainActor
    private func apply(_ me: Profile) {
        profile = me
        ProfileCache.save(me)
        stage = me.isOnboarded ? .main : .onboarding(resume: true)
    }
}
