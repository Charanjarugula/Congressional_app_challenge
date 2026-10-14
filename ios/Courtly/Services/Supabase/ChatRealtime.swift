import Foundation

/// Watches one chat's `messages` rows over Supabase Realtime so the thread updates as soon as
/// someone writes. Polling stays on as the fallback; this only makes it feel instant.
@MainActor
final class ChatRealtime {
    private let chatID: UUID
    private let onChange: () -> Void
    private var socket: URLSessionWebSocketTask?
    private var heartbeat: Task<Void, Never>?
    private var listener: Task<Void, Never>?
    private var nextRef = 0

    init(chatID: UUID, onChange: @escaping () -> Void) {
        self.chatID = chatID
        self.onChange = onChange
    }

    func connect() async {
        guard socket == nil, let session = try? await SupabaseClient.shared.validSession() else { return }
        guard var components = URLComponents(url: AppConfig.supabaseURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "wss"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: AppConfig.supabaseAnonKey),
            URLQueryItem(name: "vsn", value: "1.0.0"),
        ]
        guard let url = components.url else { return }

        let task = URLSession.shared.webSocketTask(with: url)
        socket = task
        task.resume()
        send(event: "phx_join", topic: topic, payload: [
            "config": [
                "postgres_changes": [[
                    "event": "INSERT",
                    "schema": "public",
                    "table": "messages",
                    "filter": "chat_id=eq.\(chatID.uuidString.lowercased())",
                ]],
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
        }
    }

    func disconnect() {
        heartbeat?.cancel()
        heartbeat = nil
        listener?.cancel()
        listener = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
    }

    private var topic: String {
        "realtime:chat-\(chatID.uuidString.lowercased())"
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
