import Foundation

/// Watches inserts into one table over Supabase Realtime (optionally filtered to one row key) and
/// calls back when something lands, so screens refresh at once. Polling stays on as the fallback;
/// this only makes things feel instant. Reconnects by itself if the socket drops.
@MainActor
final class RealtimeListener {
    private let table: String
    private let filter: String?
    private let events: String
    private let onChange: () -> Void
    private var socket: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private var nextRef = 0
    private var isStopped = false

    /// `filter` is a PostgREST-style condition such as `chat_id=eq.<uuid>`; nil means every row
    /// the signed-in player is allowed to see. `events` is `INSERT` (default), `UPDATE` or `*`.
    init(table: String, filter: String? = nil, events: String = "INSERT", onChange: @escaping () -> Void) {
        self.table = table
        self.filter = filter
        self.events = events
        self.onChange = onChange
    }

    func connect() async {
        guard socket == nil, !isStopped, let session = try? await SupabaseClient.shared.validSession() else { return }
        guard var components = URLComponents(url: AppConfig.supabaseURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "wss"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: AppConfig.supabaseAnonKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = components.url else { return }

        var change: [String: Any] = ["event": events, "schema": "public", "table": table]
        if let filter { change["filter"] = filter }

        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        send(event: "phx_join", topic: topic, payload: [
            "config": [
                "postgres_changes": [change],
                "broadcast": ["self": false],
                "presence": ["key": ""],
            ],
            "access_token": session.accessToken,
        ])

        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                self?.send(event: "heartbeat", topic: "phoenix", payload: [:])
            }
        }
        listener = Task { [weak self] in
            while !Task.isCancelled, let live = self?.socket {
                guard let message = try? await live.receive() else { break }
                self?.handle(message)
            }
            // The socket closed under us: wait a little and try again unless we were stopped.
            // This task is the listener itself, so it must not cancel itself here.
            guard !Task.isCancelled, let self, !self.isStopped else { return }
            self.dropSocket(cancellingListener: false)
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, !self.isStopped else { return }
            await self.connect()
        }
    }

    func disconnect() {
        isStopped = true
        dropSocket()
    }

    private func dropSocket(cancellingListener: Bool = true) {
        heartbeat?.cancel()
        heartbeat = nil
        if cancellingListener { listener?.cancel() }
        listener = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private var topic: String {
        let suffix = filter?.replacingOccurrences(of: "=eq.", with: "-") ?? "all"
        return "realtime:\(table)-\(suffix)-\(events == "*" ? "any" : events)".lowercased()
    }

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
              let event = object["event"] as? String
        else { return }
        if event == "postgres_changes" {
            onChange()
        }
    }
}
