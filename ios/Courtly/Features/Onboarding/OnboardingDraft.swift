import Foundation
import Observation

/// Everything the onboarding steps collect. Sent to the backend on the last screen.
@Observable
final class OnboardingDraft {
    var firstName = ""
    var lastName = ""
    var birthday: Date = Calendar.current.date(byAdding: .year, value: -25, to: .now) ?? .now
    var gender: Gender?
    var level: PlayerLevel?
    var formats: Set<PlayFormat> = []
    var homeArea: HomeArea?
    var radius: TravelRadius = .ten
    var availability = AvailabilityMask()
    var busyThisWeek = AvailabilityMask()
    var calendar: CalendarConnection?
    var contactsGranted = false
    var notificationsEnabled = false

    /// Players must be 13 or older: US law (COPPA) requires parental consent below that.
    static let minimumAge = 13

    var meetsMinimumAge: Bool {
        let years = Calendar.current.dateComponents([.year], from: birthday, to: .now).year ?? 0
        return years >= Self.minimumAge
    }

    var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Prefill from a profile that was started on another device or before the app was killed.
    func load(from profile: Profile) {
        firstName = profile.firstName
        lastName = profile.lastName
        if let birthday = profile.birthday, let date = Self.dateFormatter.date(from: birthday) { self.birthday = date }
        gender = profile.gender
        level = profile.level
        formats = Set(profile.formats)
        homeArea = profile.homeArea
        radius = profile.radius
        availability = profile.availability
        busyThisWeek = profile.busyThisWeek
        if profile.calendarProvider != .none {
            calendar = CalendarConnection(provider: profile.calendarProvider, detail: "Synced")
        }
    }

    /// The `update_profile` patch.
    func makePatch(accountEmail: String?) -> [String: Any] {
        var patch: [String: Any] = [
            "first_name": trimmedFirstName,
            "last_name": trimmedLastName,
            "birthday": Self.dateFormatter.string(from: birthday),
            "formats": PlayFormat.allCases.filter { formats.contains($0) }.map(\.rawValue),
            "radius_mi": radius.rawValue,
            "availability_mask": Int(availability.rawValue),
            "busy_mask_week": Int(busyThisWeek.rawValue),
            "calendar_provider": (calendar?.provider ?? CalendarProvider.none).rawValue,
        ]
        if let gender { patch["gender"] = gender.rawValue }
        if let level { patch["level"] = level.rawValue }
        if let homeArea {
            patch["area_label"] = homeArea.label
            patch["home_lat"] = homeArea.latitude
            patch["home_lng"] = homeArea.longitude
            if let zip = homeArea.zip { patch["zip"] = zip }
        }
        if let accountEmail, !accountEmail.isEmpty {
            patch["email_hash"] = ContactsService.hash(accountEmail.lowercased())
        }
        return patch
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
