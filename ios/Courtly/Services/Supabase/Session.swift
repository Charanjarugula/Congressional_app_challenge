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
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Postgres timestamps come back like "2026-10-16T18:30:00.123456+00:00"; trim to milliseconds.
    static func parseDate(_ raw: String) -> Date? {
        let trimmed = raw.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: trimmed) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: trimmed)
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
