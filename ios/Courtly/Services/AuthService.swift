import Foundation

enum AuthProvider: Equatable {
    case apple, google
    case email(String)

    var name: String {
        switch self {
        case .apple: "apple"
        case .google: "google"
        case .email: "email"
        }
    }
}

struct AuthAccount: Codable, Equatable {
    let id: String
    let email: String?
    let provider: String
}

enum AuthError: Error {
    case cancelled
    case failed
}

/// Sign-in boundary. The onboarding screens only talk to this protocol, so swapping in
/// Supabase (Sign in with Apple, Google, email code) does not touch any view.
protocol AuthService {
    func signIn(with provider: AuthProvider) async throws -> AuthAccount
}

/// Local stand-in used until the backend is wired. Succeeds after a short delay.
struct LocalAuthService: AuthService {
    func signIn(with provider: AuthProvider) async throws -> AuthAccount {
        try await Task.sleep(for: .milliseconds(600))
        let email: String? = if case let .email(address) = provider { address } else { nil }
        return AuthAccount(id: UUID().uuidString, email: email, provider: provider.name)
    }
}

/// Single place that decides which implementations the app runs with.
enum AppEnvironment {
    static let auth: AuthService = LocalAuthService()
}
