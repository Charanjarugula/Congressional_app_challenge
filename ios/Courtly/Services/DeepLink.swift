import Foundation
import Observation

/// Where a push notification points. Mirrors the `deep_link` the backend writes:
/// `courtly://play`, `courtly://hit/<id>`, `courtly://request/<id>`, `courtly://chat/<id>`,
/// `courtly://check/<hit id>/<player id>`.
enum DeepLink: Equatable {
    case play
    case hit(UUID)
    case request(UUID)
    case chat(UUID)
    case check(hitID: UUID, playerID: UUID)

    init?(string: String) {
        guard let url = URL(string: string), url.scheme == "courtly", let host = url.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch (host, parts.count) {
        case ("play", _): self = .play
        case ("hit", 1):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            self = .hit(id)
        case ("request", 1):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            self = .request(id)
        case ("chat", 1):
            guard let id = UUID(uuidString: parts[0]) else { return nil }
            self = .chat(id)
        case ("check", 2):
            guard let hitID = UUID(uuidString: parts[0]), let playerID = UUID(uuidString: parts[1]) else { return nil }
            self = .check(hitID: hitID, playerID: playerID)
        default: return nil
        }
    }

    /// From a notification's userInfo: the `deep_link` string, or the ids in `data`.
    init?(userInfo: [AnyHashable: Any]) {
        if let link = userInfo["deep_link"] as? String, let parsed = DeepLink(string: link) {
            self = parsed
            return
        }
        let data = userInfo["data"] as? [String: Any] ?? [:]
        if let chat = (data["chat_id"] as? String).flatMap({ UUID(uuidString: $0) }) {
            self = .chat(chat)
        } else if let hit = (data["hit_id"] as? String).flatMap({ UUID(uuidString: $0) }) {
            self = .hit(hit)
        } else {
            return nil
        }
    }
}

/// Hands notification taps and arrivals from the app delegate to the tab shell.
@Observable
final class DeepLinkCenter {
    static let shared = DeepLinkCenter()

    /// A link waiting to be opened. The shell clears it once it has routed.
    var pending: DeepLink?
    /// Bumped when a push arrives while the app is open, so lists refresh.
    var lastPushReceivedAt: Date?

    @MainActor
    func open(_ link: DeepLink) {
        pending = link
    }

    @MainActor
    func pushArrived() {
        lastPushReceivedAt = .now
    }
}
