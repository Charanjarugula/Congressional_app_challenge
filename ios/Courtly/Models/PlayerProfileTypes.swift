import Foundation

enum Gender: String, CaseIterable, Codable, Identifiable {
    case man, woman
    case nonBinary = "non_binary"
    case preferNot = "prefer_not"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .man: "Man"
        case .woman: "Woman"
        case .nonBinary: "Non-binary"
        case .preferNot: "Prefer not to say"
        }
    }
}

enum PlayerLevel: String, CaseIterable, Codable, Identifiable {
    case beginner, intermediate, advanced, competitive

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    var description: String {
        switch self {
        case .beginner: "New to tennis or just getting back into it."
        case .intermediate: "I can rally and play a full match."
        case .advanced: "Consistent pace, spin and placement."
        case .competitive: "I play leagues, tournaments or college."
        }
    }
}

enum PlayFormat: String, CaseIterable, Codable, Identifiable {
    case casual, singles, doubles, drills

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: "Casual hitting"
        case .singles: "Singles"
        case .doubles: "Doubles"
        case .drills: "Drills"
        }
    }

    var shortTitle: String {
        self == .casual ? "Casual" : title
    }

    var description: String {
        switch self {
        case .casual: "Rally, no score"
        case .singles: "Keep score, one on one"
        case .doubles: "Four players"
        case .drills: "Serves, footwork, patterns"
        }
    }
}

enum TravelRadius: Int, CaseIterable, Codable, Identifiable {
    case five = 5, ten = 10, fifteen = 15, twentyFive = 25

    var id: Int { rawValue }

    var title: String { "\(rawValue) mi" }
}

/// Where a player is based. Always a ZIP centroid or city, never a precise location.
struct HomeArea: Codable, Equatable {
    var label: String
    var zip: String?
    var latitude: Double
    var longitude: Double
}

enum CalendarProvider: String, Codable {
    case none, apple, google
}

struct CalendarConnection: Codable, Equatable {
    var provider: CalendarProvider
    var detail: String
}
