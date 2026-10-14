import Foundation

/// Typed wrappers around the backend's database functions. One call per user action.
enum API {
    private static var client: SupabaseClient { SupabaseClient.shared }

    enum Profile {
        static func me() async throws -> Courtly.Profile {
            try await client.rpc("get_me")
        }

        static func update(_ patch: [String: Any]) async throws -> Courtly.Profile {
            try await client.rpc("update_profile", params: ["patch": patch])
        }

        static func completeOnboarding() async throws -> Courtly.Profile {
            try await client.rpc("complete_onboarding")
        }
    }

    enum People {
        static func matchContacts(hashes: [String]) async throws -> [ContactMatch] {
            try await client.rpc("match_contacts", params: ["p_hashes": hashes])
        }

        static func suggestions(knownIDs: [UUID]) async throws -> [SuggestedPlayer] {
            try await client.rpc("get_friend_suggestions", params: ["p_known_ids": knownIDs.map(\.uuidString)])
        }

        static func addFriend(_ userID: UUID) async throws -> FriendshipResult {
            try await client.rpc("add_friend", params: ["p_user": userID.uuidString])
        }

        static func removeFriend(_ userID: UUID) async throws {
            try await client.rpc("remove_friend", params: ["p_user": userID.uuidString])
        }
    }

    enum Devices {
        private static let pendingKey = "apns_token_pending"

        /// A token the server hasn't taken yet (offline, a hiccup), kept for the next attempt.
        static var pendingToken: String? {
            get { UserDefaults.standard.string(forKey: pendingKey) }
            set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
        }

        /// The newest token is the one to keep trying: it is noted before it is sent, a failure leaves it for
        /// `retryPending`, and a success clears it only when no newer token has arrived in the meantime.
        static func register(token: String, environment: String) async {
            pendingToken = token
            do {
                try await client.rpc("register_device", params: [
                    "p_token": token,
                    "p_environment": environment,
                    "p_app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0",
                ])
                if pendingToken == token { pendingToken = nil }
            } catch {
                #if DEBUG
                print("register_device failed: \(error.localizedDescription)")
                #endif
            }
        }

        /// Sends the token the last attempt couldn't, if there is one.
        static func retryPending() async {
            guard let token = pendingToken else { return }
            await register(token: token, environment: AppConfig.apnsEnvironment)
        }
    }
}
