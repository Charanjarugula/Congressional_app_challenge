import Foundation

/// Typed wrappers around the backend's database functions. One call per user action.
enum API {
    private static var client: SupabaseClient { SupabaseClient.shared }

    /// JSON null for a missing optional argument.
    private static func nullable(_ value: Any?) -> Any { value ?? NSNull() }

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

        static func friends() async throws -> [Friend] {
            try await client.rpc("get_friends")
        }

        static func addFriend(_ userID: UUID) async throws -> FriendshipResult {
            try await client.rpc("add_friend", params: ["p_user": userID.uuidString])
        }

        static func removeFriend(_ userID: UUID) async throws {
            try await client.rpc("remove_friend", params: ["p_user": userID.uuidString])
        }

        static func search(_ query: String) async throws -> [SearchedPlayer] {
            try await client.rpc("search_players", params: ["p_query": query])
        }

        static func player(_ userID: UUID) async throws -> PlayerProfile {
            try await client.rpc("get_player", params: ["p_user": userID.uuidString])
        }

        static func block(_ userID: UUID) async throws {
            try await client.rpc("block_user", params: ["p_user": userID.uuidString])
        }

        static func unblock(_ userID: UUID) async throws {
            try await client.rpc("unblock_user", params: ["p_user": userID.uuidString])
        }

        static func report(_ userID: UUID, reason: ReportReason, details: String?, alsoBlock: Bool, hitID: UUID?) async throws {
            try await client.rpc("report_user", params: [
                "p_user": userID.uuidString,
                "p_reason": reason.rawValue,
                "p_details": nullable(details),
                "p_also_block": alsoBlock,
                "p_hit": nullable(hitID?.uuidString),
            ])
        }

        static func blocked() async throws -> [PlayerCard] {
            try await client.rpc("get_blocked_players")
        }
    }

    enum Hits {
        static func feed() async throws -> PlayFeed {
            try await client.rpc("get_play_feed")
        }

        static func mine() async throws -> MyHits {
            try await client.rpc("get_my_hits")
        }

        static func get(_ hitID: UUID) async throws -> Hit {
            try await client.rpc("get_hit", params: ["p_hit": hitID.uuidString])
        }

        static func create(courtID: UUID, startsAt: Date, durationMin: Int, format: PlayFormat, spots: Int, visibility: HitVisibility,
                           inviteChatID: UUID? = nil, inviteExpiresAt: Date? = nil) async throws -> Hit {
            try await client.rpc("create_hit", params: [
                "p_court_id": courtID.uuidString,
                "p_starts_at": JSONCoding.string(from: startsAt),
                "p_duration_min": durationMin,
                "p_format": format.rawValue,
                "p_spots": spots,
                "p_visibility": visibility.rawValue,
                "p_invite_chat_id": nullable(inviteChatID?.uuidString),
                "p_invite_expires_at": nullable(inviteExpiresAt.map(JSONCoding.string(from:))),
            ])
        }

        static func requestToJoin(_ hitID: UUID) async throws -> Hit {
            try await client.rpc("request_to_join", params: ["p_hit": hitID.uuidString])
        }

        static func respond(requestID: UUID, accept: Bool) async throws -> Hit {
            try await client.rpc("respond_to_request", params: ["p_request": requestID.uuidString, "p_accept": accept])
        }

        static func cancelRequest(_ requestID: UUID) async throws {
            try await client.rpc("cancel_request", params: ["p_request": requestID.uuidString])
        }

        static func markRequestSeen(_ requestID: UUID) async throws {
            try await client.rpc("mark_request_seen", params: ["p_request": requestID.uuidString])
        }

        static func leave(_ hitID: UUID) async throws -> Hit {
            try await client.rpc("leave_hit", params: ["p_hit": hitID.uuidString])
        }

        static func cancel(_ hitID: UUID) async throws -> Hit {
            try await client.rpc("cancel_hit", params: ["p_hit": hitID.uuidString])
        }

        static func submitAttendance(hitID: UUID, about playerID: UUID, showedUp: Bool, addFriend: Bool) async throws {
            try await client.rpc("submit_attendance", params: [
                "p_hit": hitID.uuidString,
                "p_about": playerID.uuidString,
                "p_showed_up": showedUp,
                "p_add_friend": addFriend,
            ])
        }

        static func sendInvite(hitID: UUID, chatID: UUID, targetUserID: UUID?) async throws -> HitInvite {
            try await client.rpc("send_hit_invite", params: [
                "p_hit": hitID.uuidString,
                "p_chat": chatID.uuidString,
                "p_target_user": nullable(targetUserID?.uuidString),
            ])
        }

        static func claimInvite(_ inviteID: UUID) async throws -> Hit {
            try await client.rpc("claim_invite", params: ["p_invite": inviteID.uuidString])
        }

        static func declineInvite(_ inviteID: UUID) async throws {
            try await client.rpc("decline_invite", params: ["p_invite": inviteID.uuidString])
        }
    }

    enum Courts {
        static func nearby(limit: Int = 30) async throws -> [Court] {
            try await client.rpc("get_nearby_courts", params: ["p_limit": limit])
        }

        static func add(name: String, address: String?, city: String?, latitude: Double, longitude: Double, applePlaceID: String?) async throws -> Court {
            try await client.rpc("add_court", params: [
                "p_name": name,
                "p_address": nullable(address),
                "p_city": nullable(city),
                "p_lat": latitude,
                "p_lng": longitude,
                "p_apple_place_id": nullable(applePlaceID),
            ])
        }
    }

    enum Chats {
        static func inbox() async throws -> [Chat] {
            try await client.rpc("get_inbox")
        }

        static func get(_ chatID: UUID) async throws -> Chat {
            try await client.rpc("get_chat", params: ["p_chat": chatID.uuidString])
        }

        static func page(chatID: UUID, before: Message? = nil, limit: Int = 50) async throws -> ChatPage {
            var params: [String: Any] = ["p_chat": chatID.uuidString, "p_limit": limit]
            if let before {
                params["p_before_created_at"] = JSONCoding.string(from: before.createdAt)
                params["p_before_id"] = before.id.uuidString
            }
            return try await client.rpc("get_chat_page", params: params)
        }

        static func send(chatID: UUID, clientID: UUID, body: String) async throws -> Message {
            try await client.rpc("send_message", params: [
                "p_chat": chatID.uuidString,
                "p_client_id": clientID.uuidString,
                "p_body": body,
            ])
        }

        static func markRead(_ chatID: UUID) async throws {
            try await client.rpc("mark_chat_read", params: ["p_chat": chatID.uuidString])
        }

        static func createGroup(name: String, memberIDs: [UUID]) async throws -> Chat {
            try await client.rpc("create_group_chat", params: ["p_name": name, "p_members": memberIDs.map(\.uuidString)])
        }

        static func addMembers(chatID: UUID, memberIDs: [UUID]) async throws -> Chat {
            try await client.rpc("add_chat_members", params: ["p_chat": chatID.uuidString, "p_members": memberIDs.map(\.uuidString)])
        }

        static func leave(_ chatID: UUID) async throws {
            try await client.rpc("leave_chat", params: ["p_chat": chatID.uuidString])
        }

        static func setMuted(_ chatID: UUID, muted: Bool) async throws {
            try await client.rpc("set_chat_muted", params: ["p_chat": chatID.uuidString, "p_muted": muted])
        }
    }

    enum Devices {
        private static let tokenKey = "apns_token"
        private static let pendingKey = "apns_token_pending"

        /// The APNs token this device last registered, kept so sign-out can take it back.
        static var storedToken: String? {
            get { UserDefaults.standard.string(forKey: tokenKey) }
            set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
        }

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
                storedToken = token
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

        /// Stops pushes for this device; the next account to sign in registers it again.
        static func unregisterStored() async {
            pendingToken = nil
            guard let token = storedToken else { return }
            try? await client.rpc("unregister_device", params: ["p_token": token])
            storedToken = nil
        }
    }
}
