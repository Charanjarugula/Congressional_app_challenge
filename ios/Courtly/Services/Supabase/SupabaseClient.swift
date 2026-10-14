import Foundation

enum SupabaseError: LocalizedError, Equatable {
    case notSignedIn
    case http(status: Int, message: String)
    /// A `raise exception 'code'` from a database function, e.g. "spot_taken".
    case backend(code: String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You’re signed out."
        case let .http(status, message): "Request failed (\(status)): \(message)"
        case let .backend(code): BackendMessages.text(for: code)
        case let .decoding(detail): "Unexpected response: \(detail)"
        }
    }

    var code: String? {
        if case let .backend(code) = self { return code }
        return nil
    }
}

/// Thin client for Supabase's REST surface: auth, database functions, Edge Functions, storage.
/// Every data call goes through a database function, so this is all the app needs.
actor SupabaseClient {
    static let shared = SupabaseClient(url: AppConfig.supabaseURL, anonKey: AppConfig.supabaseAnonKey)

    private let baseURL: URL
    private let anonKey: String
    private let urlSession = URLSession(configuration: .default)
    private let keychainAccount = "supabase.session"
    private var refreshTask: Task<Session, Error>?

    private(set) var session: Session? {
        didSet {
            if let session, let data = try? JSONEncoder().encode(session) {
                Keychain.save(data, account: keychainAccount)
            } else if session == nil {
                Keychain.delete(account: keychainAccount)
            }
        }
    }

    init(url: URL, anonKey: String) {
        baseURL = url
        self.anonKey = anonKey
        if let data = Keychain.load(account: keychainAccount), let saved = try? JSONDecoder().decode(Session.self, from: data) {
            session = saved
        }
    }

    var isSignedIn: Bool { session != nil }

    // MARK: - Auth

    /// Native Sign in with Apple / Google: hand Supabase the provider's id token.
    func signIn(provider: String, idToken: String, nonce: String?) async throws -> Session {
        var body: [String: Any] = ["provider": provider, "id_token": idToken]
        if let nonce { body["nonce"] = nonce }
        return try await tokenGrant(path: "/auth/v1/token?grant_type=id_token", body: body, provider: provider)
    }

    func sendEmailCode(email: String) async throws {
        _ = try await request("/auth/v1/otp", method: "POST", body: ["email": email, "create_user": true], authorized: false)
    }

    func verifyEmailCode(email: String, code: String) async throws -> Session {
        try await tokenGrant(path: "/auth/v1/verify", body: ["type": "email", "email": email, "token": code], provider: "email")
    }

    func signInWithPassword(email: String, password: String) async throws -> Session {
        try await tokenGrant(path: "/auth/v1/token?grant_type=password", body: ["email": email, "password": password], provider: "email")
    }

    func signOut() async {
        if session != nil {
            _ = try? await request("/auth/v1/logout", method: "POST", body: nil, authorized: true)
        }
        session = nil
    }

    /// The current session, refreshed if it is about to expire. Throws `notSignedIn` when there is none.
    func validSession() async throws -> Session {
        guard let current = session else { throw SupabaseError.notSignedIn }
        guard current.needsRefresh else { return current }
        if let refreshTask { return try await refreshTask.value }
        let task = Task<Session, Error> {
            defer { refreshTask = nil }
            do {
                return try await tokenGrant(path: "/auth/v1/token?grant_type=refresh_token", body: ["refresh_token": current.refreshToken], provider: current.provider)
            } catch let error as SupabaseError {
                if case let .http(status, _) = error, status == 400 || status == 401 {
                    session = nil
                    throw SupabaseError.notSignedIn
                }
                throw error
            }
        }
        refreshTask = task
        return try await task.value
    }

    private func tokenGrant(path: String, body: [String: Any], provider: String?) async throws -> Session {
        let data = try await request(path, method: "POST", body: body, authorized: false)
        let token: TokenResponse
        do {
            token = try JSONCoding.decoder.decode(TokenResponse.self, from: data)
        } catch {
            throw SupabaseError.decoding(String(describing: error))
        }
        let fresh = token.session(provider: provider)
        session = fresh
        return fresh
    }

    // MARK: - Database functions

    func rpc<T: Decodable>(_ function: String, params: [String: Any] = [:]) async throws -> T {
        let data = try await request("/rest/v1/rpc/\(function)", method: "POST", body: params, authorized: true)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw SupabaseError.decoding("\(function): \(error)")
        }
    }

    func rpc(_ function: String, params: [String: Any] = [:]) async throws {
        _ = try await request("/rest/v1/rpc/\(function)", method: "POST", body: params, authorized: true)
    }

    // MARK: - Edge Functions

    func invoke<T: Decodable>(_ function: String, body: [String: Any] = [:]) async throws -> T {
        let data = try await request("/functions/v1/\(function)", method: "POST", body: body, authorized: true)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw SupabaseError.decoding("\(function): \(error)")
        }
    }

    // MARK: - Storage

    func upload(bucket: String, path: String, data: Data, contentType: String) async throws {
        var headers = ["Content-Type": contentType, "x-upsert": "true"]
        headers["Cache-Control"] = "max-age=3600"
        _ = try await request("/storage/v1/object/\(bucket)/\(path)", method: "POST", rawBody: data, headers: headers, authorized: true)
    }

    nonisolated func publicURL(bucket: String, path: String) -> URL {
        baseURL.appending(path: "/storage/v1/object/public/\(bucket)/\(path)")
    }

    // MARK: - Transport

    private func request(_ path: String, method: String, body: [String: Any]?, authorized: Bool, headers: [String: String] = [:]) async throws -> Data {
        var raw: Data?
        if let body {
            raw = try JSONSerialization.data(withJSONObject: body)
        }
        var allHeaders = headers
        if raw != nil { allHeaders["Content-Type"] = "application/json" }
        return try await request(path, method: method, rawBody: raw, headers: allHeaders, authorized: authorized)
    }

    private func request(_ path: String, method: String, rawBody: Data?, headers: [String: String], authorized: Bool) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw SupabaseError.http(status: 0, message: "bad path \(path)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = method
        urlRequest.httpBody = rawBody
        urlRequest.setValue(anonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized {
            let current = try await validSession()
            urlRequest.setValue("Bearer \(current.accessToken)", forHTTPHeaderField: "Authorization")
        } else {
            urlRequest.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        }
        for (key, value) in headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await urlSession.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.http(status: 0, message: "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.error(status: http.statusCode, data: data)
        }
        return data
    }

    private static func error(status: Int, data: Data) -> SupabaseError {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .http(status: status, message: String(data: data, encoding: .utf8) ?? "")
        }
        // Database functions raise short codes; PostgREST reports them as P0001 with the code as message.
        if let code = object["code"] as? String, code == "P0001", let message = object["message"] as? String {
            return .backend(code: message)
        }
        let message = (object["message"] as? String)
            ?? (object["msg"] as? String)
            ?? (object["error_description"] as? String)
            ?? (object["error"] as? String)
            ?? "unknown error"
        return .http(status: status, message: message)
    }
}
