import Foundation
import Observation

/// Everything the onboarding steps collect. Sent to the backend on the last screen.
@Observable
final class OnboardingDraft {
    var firstName = ""
    var lastName = ""
    var gender: Gender?
    var level: PlayerLevel?
    var formats: Set<PlayFormat> = []
    var homeArea: HomeArea?
    var radius: TravelRadius = .ten
    var availability = AvailabilityMask()
    var busyThisWeek = AvailabilityMask()
    var calendar: CalendarConnection?
    var contactsGranted = false

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

    /// The `update_profile` patch. Contact hashes are the server's: it hashes the verified sign-in email itself.
    func makePatch() -> [String: Any] {
        var patch: [String: Any] = [
            "first_name": trimmedFirstName,
            "last_name": trimmedLastName,
            "formats": PlayFormat.allCases.filter { formats.contains($0) }.map(\.rawValue),
            "radius_mi": radius.rawValue,
            "availability_mask": Int(availability.rawValue),
            "busy_mask_week": Int(busyThisWeek.rawValue),
            "calendar_provider": (calendar?.provider ?? CalendarProvider.none).rawValue,
            "time_zone": TimeZone.current.identifier,
        ]
        if let gender { patch["gender"] = gender.rawValue }
        if let level { patch["level"] = level.rawValue }
        if let homeArea {
            patch["area_label"] = homeArea.label
            patch["home_lat"] = homeArea.latitude
            patch["home_lng"] = homeArea.longitude
            if let zip = homeArea.zip { patch["zip"] = zip }
        }
        return patch
    }
}
