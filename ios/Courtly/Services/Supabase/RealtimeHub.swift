import Foundation

/// One Supabase Realtime connection for the whole app. Screens subscribe to inserts (or any event)
/// on a table, optionally filtered to one row key, and are called back when something lands so
/// they can refresh at once. Row-level security decides which rows each player hears about.
/// Polling stays on everywhere as the fallback; this only makes things feel instant.
@MainActor
final class RealtimeHub {
    static let shared = RealtimeHub()

    struct Subscription {
        fileprivate let topic: String
        fileprivate let id: UUID
    }

    private struct Channel {
        var config: [String: Any]
        var handlers: [UUID: () -> Void]
    }

    private var socket: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private var reconnect: Task<Void, Never>?
    private var channels: [String: Channel] = [:]
    private var joined: Set<String> = []
    private var nextRef = 0
    private var accessToken: String?

    /// True while the socket is open; screens poll slower then.
    var isConnected: Bool { socket != nil }

    /// `filter` is a PostgREST-style condition such as `chat_id=eq.<uuid>`; nil means every row the
    /// signed-in player is allowed to see. `events` is `INSERT` (default), `UPDATE` or `*`.
    func subscribe(table: String, filter: String? = nil, events: String = "INSERT", onChange: @escaping () -> Void) -> Subscription {
        let suffix = filter?.replacingOccurrences(of: "=eq.", with: "-") ?? "all"
        let topic = "realtime:\(table)-\(suffix)-\(events == "*" ? "any" : events)".lowercased()
        let id = UUID()
        if var channel = channels[topic] {
            channel.handlers[id] = onChange
            channels[topic] = channel
        } else {
            var change: [String: Any] = ["event": events, "schema": "public", "table": table]
            if let filter { change["filter"] = filter }
            channels[topic] = Channel(
                config: ["postgres_changes": [change], "broadcast": ["self": false], "presence": ["key": ""]],
                handlers: [id: onChange]
            )
            Task { await connectAndJoin() }
        }
        return Subscription(topic: topic, id: id)
    }

    /// Forget every subscription and close the socket. Called on sign-out so the next player
    /// never inherits channels joined with someone else's token.
    func reset() {
        channels = [:]
        dropSocket()
        reconnect?.cancel()
        reconnect = nil
        accessToken = nil
    }

    func unsubscribe(_ subscription: Subscription) {
        guard var channel = channels[subscription.topic] else { return }
        channel.handlers[subscription.id] = nil
        if channel.handlers.isEmpty {
            channels[subscription.topic] = nil
            if joined.contains(subscription.topic) {
                send(event: "phx_leave", topic: subscription.topic, payload: [:])
                joined.remove(subscription.topic)
            }
            if channels.isEmpty { dropSocket() }
        } else {
            channels[subscription.topic] = channel
        }
    }

    // MARK: - Connection

    private func connectAndJoin() async {
        if socket == nil {
            guard !channels.isEmpty else { return }
            guard let session = try? await SupabaseClient.shared.validSession() else {
                scheduleReconnect()   // offline, or the session is mid-refresh: try again shortly
                return
            }
            guard var components = URLComponents(url: AppConfig.supabaseURL, resolvingAgainstBaseURL: false) else { return }
            components.scheme = "wss"
            components.path = "/realtime/v1/websocket"
            components.queryItems = [
                URLQueryItem(name: "apikey", value: AppConfig.supabaseAnonKey),
                URLQueryItem(name: "vsn", value: "1.0.0"),
            ]
            guard let url = components.url, socket == nil else { return }
            let task = URLSession.shared.webSocketTask(with: url)
            socket = task
            joined = []
            task.resume()
            startHeartbeat()
            startListening(on: task)
            accessToken = session.accessToken
            joinPending(accessToken: session.accessToken)
        } else if let session = try? await SupabaseClient.shared.validSession() {
            accessToken = session.accessToken
            joinPending(accessToken: session.accessToken)
        }
    }

    /// The channel token expires with the session (about an hour). Hand every joined channel the
    /// refreshed token so the server keeps delivering.
    private func refreshTokenIfNeeded() async {
        guard socket != nil, let session = try? await SupabaseClient.shared.validSession(), session.accessToken != accessToken else { return }
        accessToken = session.accessToken
        for topic in joined {
            send(event: "access_token", topic: topic, payload: ["access_token": session.accessToken])
        }
    }

    /// The server closed one channel (token expiry, a rejected join): join it again with a fresh token.
    private func rejoin(_ topic: String) {
        joined.remove(topic)
        guard channels[topic] != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await self?.connectAndJoin()
        }
    }

    private func joinPending(accessToken: String) {
        for topic in channels.keys where !joined.contains(topic) {
            guard let channel = channels[topic] else { continue }
            send(event: "phx_join", topic: topic, payload: ["config": channel.config, "access_token": accessToken])
            joined.insert(topic)
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                self?.send(event: "heartbeat", topic: "phoenix", payload: [:])
                await self?.refreshTokenIfNeeded()
            }
        }
    }

    private func startListening(on task: URLSessionWebSocketTask) {
        listener?.cancel()
        listener = Task { [weak self] in
            while !Task.isCancelled {
                guard let message = try? await task.receive() else { break }
                self?.handle(message)
            }
            guard !Task.isCancelled, let self else { return }
            // The socket closed under us. Drop it, keep the subscriptions, and try again shortly.
            self.dropSocket(cancellingListener: false)
            self.scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnect?.cancel()
        reconnect = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, !self.channels.isEmpty else { return }
            await self.connectAndJoin()
        }
    }

    private func dropSocket(cancellingListener: Bool = true) {
        heartbeat?.cancel()
        heartbeat = nil
        if cancellingListener {
            listener?.cancel()
        }
        listener = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        joined = []
    }

    // MARK: - Frames

    private func send(event: String, topic: String, payload: [String: Any]) {
        nextRef += 1
        let frame: [String: Any] = ["topic": topic, "event": event, "payload": payload, "ref": String(nextRef)]
        guard let data = try? JSONSerialization.data(withJSONObject: frame), let text = String(data: data, encoding: .utf8) else { return }
        socket?.send(.string(text)) { _ in }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        guard case let .string(text) = message,
              let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String,
              let topic = object["topic"] as? String
        else { return }
        switch event {
        case "postgres_changes":
            channels[topic]?.handlers.values.forEach { $0() }
        case "phx_error", "phx_close":
            if topic != "phoenix" { rejoin(topic) }
        case "phx_reply":
            let payload = object["payload"] as? [String: Any]
            if payload?["status"] as? String == "error", topic != "phoenix" { rejoin(topic) }
        case "system":
            let payload = object["payload"] as? [String: Any]
            if payload?["status"] as? String == "error", topic != "phoenix" { rejoin(topic) }
        default:
            break
        }
    }
}
