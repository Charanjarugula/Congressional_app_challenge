import Foundation

/// A signed-in user's tokens, persisted in the keychain.
struct Session: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
    var email: String?
    /// "apple", "google" or "email"; shown on the Account screen.
    var provider: String?

    var needsRefresh: Bool {
        expiresAt.timeIntervalSinceNow < 60
    }
}

/// What the auth endpoints return for a token grant.
struct TokenResponse: Decodable {
    struct User: Decodable {
        let id: UUID
        let email: String?
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Double
    let user: User

    func session(provider: String?) -> Session {
        Session(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSinceNow: expiresIn),
            userID: user.id,
            email: user.email,
            provider: provider
        )
    }
}

enum JSONCoding {
    /// "2026-10-16T22:30:00.000Z", which Postgres and `parseDate` both accept.
    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    // ISO8601DateFormatter is thread-safe; one of each for every date the app decodes.
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Postgres timestamps come back like "2026-10-16T18:30:00.123456+00:00", and it trims trailing
    /// zeros ("…:00.5+00:00"). The formatter wants exactly three fraction digits, so normalize first.
    static func parseDate(_ raw: String) -> Date? {
        let text = withThreeFractionDigits(raw)
        return fractional.date(from: text) ?? plain.date(from: text)
    }

    private static func withThreeFractionDigits(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: ".") else { return raw }
        let start = raw.index(after: dot)
        let end = raw[start...].firstIndex { !$0.isNumber } ?? raw.endIndex
        let digits = raw[start..<end]
        guard !digits.isEmpty else { return raw }
        let fixed = String(digits.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
        return String(raw[..<dot]) + "." + fixed + String(raw[end...])
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date \(raw)")
            }
            return date
        }
        return decoder
    }()

    /// Mirror of `decoder` for on-disk snapshots.
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(string(from: date))
        }
        return encoder
    }()
}
