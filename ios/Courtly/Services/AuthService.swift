import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

enum AuthError: LocalizedError {
    case cancelled
    case googleNotConfigured
    case missingToken
    case invalidCode

    var errorDescription: String? {
        switch self {
        case .cancelled: "Sign-in was cancelled."
        case .googleNotConfigured: "Google sign-in isn’t set up yet. Use Apple or email for now."
        case .missingToken: "The sign-in provider didn’t return a token."
        case .invalidCode: "That code didn’t work. Check the email and try again."
        }
    }
}

/// Sign-in boundary used by the onboarding screens.
protocol AuthService {
    /// Returns the name Apple shares on the first sign-in, so onboarding can prefill it.
    func signInWithApple() async throws -> PersonNameComponents?
    func signInWithGoogle() async throws
    func sendEmailCode(to email: String) async throws
    func verifyEmailCode(email: String, code: String) async throws
}

/// Native Apple and Google sign-in, email codes, and the App Review path, all ending in a Supabase session.
final class SupabaseAuthService: AuthService {
    private let client = SupabaseClient.shared
    private let apple = AppleSignInCoordinator()
    private let web = WebAuthCoordinator()

    // MARK: Apple

    func signInWithApple() async throws -> PersonNameComponents? {
        let rawNonce = Self.randomString(length: 32)
        let credential = try await apple.signIn(nonceHash: Self.sha256(rawNonce))
        guard let tokenData = credential.identityToken, let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.missingToken
        }
        _ = try await client.signIn(provider: "apple", idToken: idToken, nonce: rawNonce)

        // Apple requires revoking the token on account deletion; the code is single-use and short-lived,
        // so it is exchanged right away. Failure here must not block sign-in.
        if let codeData = credential.authorizationCode, let code = String(data: codeData, encoding: .utf8) {
            Task { try? await API.Account.exchangeAppleCode(code) }
        }
        return credential.fullName
    }

    // MARK: Google (OAuth with PKCE through the system web session; no SDK)

    func signInWithGoogle() async throws {
        let clientID = AppConfig.googleClientID
        guard !clientID.isEmpty else { throw AuthError.googleNotConfigured }
        let scheme = "com.googleusercontent.apps." + clientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomString(length: 64)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let rawNonce = Self.randomString(length: 32)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "nonce", value: rawNonce),
        ]
        let callback = try await web.authenticate(url: components.url!, callbackScheme: scheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.missingToken
        }

        var tokenRequest = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        tokenRequest.httpMethod = "POST"
        tokenRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        tokenRequest.httpBody = [
            "client_id": clientID, "code": code, "code_verifier": verifier,
            "redirect_uri": redirectURI, "grant_type": "authorization_code",
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&").data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: tokenRequest)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let idToken = object["id_token"] as? String else {
            throw AuthError.missingToken
        }
        _ = try await client.signIn(provider: "google", idToken: idToken, nonce: rawNonce)
    }

    // MARK: Email

    func sendEmailCode(to email: String) async throws {
        if email == AppConfig.reviewerEmail { return } // the reviewer's code is a password, nothing to send
        try await client.sendEmailCode(email: email)
    }

    func verifyEmailCode(email: String, code: String) async throws {
        do {
            if email == AppConfig.reviewerEmail {
                _ = try await client.signInWithPassword(email: email, password: code)
            } else {
                _ = try await client.verifyEmailCode(email: email, code: code)
            }
        } catch let error as SupabaseError {
            if case let .http(status, _) = error, status == 400 || status == 401 || status == 403 {
                throw AuthError.invalidCode
            }
            throw error
        }
    }

    // MARK: Helpers

    private static func randomString(length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { alphabet[Int($0) % alphabet.count] })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Presents the native Sign in with Apple sheet and returns the credential.
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?

    @MainActor
    func signIn(nonceHash: String) async throws -> ASAuthorizationAppleIDCredential {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonceHash
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
            continuation?.resume(returning: credential)
        } else {
            continuation?.resume(throwing: AuthError.missingToken)
        }
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authError = error as? ASAuthorizationError, authError.code == .canceled {
            continuation?.resume(throwing: AuthError.cancelled)
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        WebAuthCoordinator.keyWindow ?? ASPresentationAnchor()
    }
}

/// Runs an OAuth flow in the system web session and returns the callback URL.
final class WebAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    /// Delegate callbacks arrive on the main thread, so the lookup can assume the main actor.
    static var keyWindow: UIWindow? {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
        }
    }

    @MainActor
    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.missingToken)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        Self.keyWindow ?? ASPresentationAnchor()
    }
}

/// Single place that decides which implementations the app runs with.
enum AppEnvironment {
    static let auth: AuthService = SupabaseAuthService()
}
