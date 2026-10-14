import Foundation
import Observation

/// App-wide state: whether the player has finished onboarding, and the profile collected there.
/// Persisted in UserDefaults until the backend owns the profile.
@Observable
final class AppSession {
    enum Stage: Equatable {
        case onboarding, main
    }

    private(set) var stage: Stage
    private(set) var profile: LocalProfile?

    private static let profileKey = "courtly.localProfile"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.profileKey),
           let saved = try? JSONDecoder().decode(LocalProfile.self, from: data) {
            profile = saved
            stage = .main
        } else {
            profile = nil
            stage = .onboarding
        }
    }

    func completeOnboarding(with draft: OnboardingDraft) {
        let newProfile = draft.makeProfile()
        profile = newProfile
        if let data = try? JSONEncoder().encode(newProfile) {
            UserDefaults.standard.set(data, forKey: Self.profileKey)
        }
        stage = .main
    }

    func signOut() {
        UserDefaults.standard.removeObject(forKey: Self.profileKey)
        profile = nil
        stage = .onboarding
    }
}
