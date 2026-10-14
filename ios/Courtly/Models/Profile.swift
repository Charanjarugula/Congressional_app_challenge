import Foundation

/// The signed-in player's own profile as the backend returns it (`get_me`, `update_profile`).
struct Profile: Codable, Equatable {
    let id: UUID
    var firstName: String
    var lastName: String
    var photoPath: String?
    var birthday: String?          // yyyy-MM-dd
    var gender: Gender?
    var level: PlayerLevel?
    var formats: [PlayFormat]
    var zip: String?
    var areaLabel: String?
    var homeLat: Double?
    var homeLng: Double?
    var radiusMi: Int
    var availabilityMask: Int32
    var busyMaskWeek: Int32?
    var calendarProvider: CalendarProvider
    var phoneE164: String?
    var hitVisibility: String
    var hitsPlayed: Int
    var coachMarksDone: Bool
    var onboardingCompletedAt: Date?
    var blockedCount: Int

    var isOnboarded: Bool { onboardingCompletedAt != nil }

    var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    /// Others only ever see "Maya R."
    var publicName: String {
        guard let initial = lastName.first else { return firstName }
        return "\(firstName) \(initial)."
    }

    var availability: AvailabilityMask { AvailabilityMask(rawValue: availabilityMask) }
    var busyThisWeek: AvailabilityMask { AvailabilityMask(rawValue: busyMaskWeek ?? 0) }
    var radius: TravelRadius { TravelRadius(rawValue: radiusMi) ?? .ten }

    /// How other players see this profile.
    var card: PlayerCard {
        PlayerCard(id: id, firstName: firstName, lastInitial: lastName.first.map(String.init), photoPath: photoPath,
                   level: level, areaLabel: areaLabel, hitsPlayed: hitsPlayed, formats: formats,
                   availabilityMask: availabilityMask, busyMaskWeek: busyMaskWeek)
    }

    var homeArea: HomeArea? {
        guard let label = areaLabel, let lat = homeLat, let lng = homeLng else { return nil }
        return HomeArea(label: label, zip: zip, latitude: lat, longitude: lng)
    }
}

/// Small on-disk copy so the app can paint before the network answers.
enum ProfileCache {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "profile.json")
    }

    static func load() -> Profile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONCoding.decoder.decode(Profile.self, from: data)
    }

    static func save(_ profile: Profile?) {
        guard let profile else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(profile) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
