import Foundation

/// What onboarding collected, persisted on device so the app can show it before the backend exists.
struct LocalProfile: Codable, Equatable {
    var accountID: String
    var accountEmail: String?
    var accountProvider: String
    var firstName: String
    var lastName: String
    var birthday: Date
    var gender: Gender
    var level: PlayerLevel
    var formats: [PlayFormat]
    var homeArea: HomeArea?
    var radius: TravelRadius
    var availability: AvailabilityMask
    var busyThisWeek: AvailabilityMask
    var calendar: CalendarConnection?
    var addedPlayerIDs: [String]
    var notificationsEnabled: Bool

    var displayName: String {
        "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces)
    }

    /// Others only ever see "Maya R."
    var publicName: String {
        guard let initial = lastName.first else { return firstName }
        return "\(firstName) \(initial)."
    }
}
