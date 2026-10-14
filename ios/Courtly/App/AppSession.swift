import Foundation
import Observation
import UserNotifications

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

    private var sessionLostObserver: NSObjectProtocol?
    private var draftSaveTask: Task<Void, Never>?

    init() {
        profile = ProfileCache.load()
        // A refresh the server rejected means this session is over; the app goes back to Welcome.
        sessionLostObserver = NotificationCenter.default.addObserver(forName: .courtlySessionLost, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.stage != .loading else { return }
                await self.signOut()
            }
        }
        Task { @MainActor in await restore() }
    }

    /// On launch: no session → welcome; session + unfinished profile → resume; otherwise the app.
    /// A suspended, deleted or missing account signs out; anything else keeps what the device has.
    @MainActor
    func restore() async {
        do {
            _ = try await client.validSession()
            let me = try await API.Profile.me()
            apply(me)
        } catch SupabaseError.notSignedIn {
            await signOut()
        } catch SupabaseError.http(status: 401, message: _) {
            // The token is stale before its clock says so, or the gateway said no. One refresh decides:
            // a session the server still honors carries on; one it rejects ends here.
            if (try? await client.refreshNow()) != nil, let me = try? await API.Profile.me() {
                apply(me)
            } else if await client.session == nil {
                await signOut()
            } else {
                keepWhatTheDeviceHas()
            }
        } catch let SupabaseError.backend(code) where ["account_suspended", "account_deleted", "no_profile"].contains(code) {
            await signOut()
            alert = AppAlert(title: "Signed out", message: BackendMessages.text(for: code))
        } catch {
            keepWhatTheDeviceHas()
        }
    }

    /// Offline or a backend hiccup: carry on with the cached profile.
    @MainActor
    private func keepWhatTheDeviceHas() {
        if let cached = profile, cached.isOnboarded {
            stage = .main
        } else {
            stage = .onboarding(resume: profile != nil)
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
    func completeOnboarding(with draft: OnboardingDraft) async throws {
        await draftSaveTask?.value   // earlier step saves land first, so none can overwrite the final answers
        _ = try await API.Profile.update(draft.makePatch())
        let me = try await API.Profile.completeOnboarding()
        apply(me)
    }

    /// Saves what onboarding has collected so far, so a player who quits picks up where they left off.
    /// Saves run one after another, in the order the steps were answered.
    @MainActor
    func saveDraft(_ draft: OnboardingDraft) {
        let patch = draft.makePatch()
        let previous = draftSaveTask
        draftSaveTask = Task {
            await previous?.value
            _ = try? await API.Profile.update(patch)
        }
    }

    /// Saves part of the profile (`update_profile` only touches the keys in the patch).
    @MainActor
    func updateProfile(_ patch: [String: Any]) async throws {
        let me = try await API.Profile.update(patch)
        profile = me
        ProfileCache.save(me)
    }

    /// The server removes hits, chats, photos and the sign-in; then the device forgets everything.
    @MainActor
    func deleteAccount() async throws {
        struct Receipt: Decodable {
            let deleted: Bool?
        }
        let _: Receipt = try await client.invoke("delete-account", body: ["mode": "full"])
        await signOut()
    }

    func currentSession() async -> Session? {
        await client.session
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

    /// Server first (device token, sign-out), then everything the device remembers about the player.
    @MainActor
    func signOut() async {
        RealtimeHub.shared.reset()
        await API.Devices.unregisterStored()
        await client.signOut()
        profile = nil
        ProfileCache.save(nil)
        SnapshotCache.clear()
        DeepLinkCenter.shared.pending = nil
        try? await UNUserNotificationCenter.current().setBadgeCount(0)
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
