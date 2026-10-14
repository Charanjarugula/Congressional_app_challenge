import Foundation
import Observation

/// Everything the onboarding steps collect. One instance lives for the whole flow and is
/// turned into a `LocalProfile` on the last screen.
@Observable
final class OnboardingDraft {
    var account: AuthAccount?
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
    var addedPlayerIDs: Set<String> = []
    var notificationsEnabled = false

    var isAdult: Bool {
        let years = Calendar.current.dateComponents([.year], from: birthday, to: .now).year ?? 0
        return years >= 18
    }

    var trimmedFirstName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedLastName: String {
        lastName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeProfile() -> LocalProfile {
        LocalProfile(
            accountID: account?.id ?? UUID().uuidString,
            accountEmail: account?.email,
            accountProvider: account?.provider ?? "unknown",
            firstName: trimmedFirstName.isEmpty ? "Player" : trimmedFirstName,
            lastName: trimmedLastName,
            birthday: birthday,
            gender: gender ?? .preferNot,
            level: level ?? .intermediate,
            formats: PlayFormat.allCases.filter { formats.contains($0) },
            homeArea: homeArea,
            radius: radius,
            availability: availability,
            busyThisWeek: busyThisWeek,
            calendar: calendar,
            addedPlayerIDs: Array(addedPlayerIDs).sorted(),
            notificationsEnabled: notificationsEnabled
        )
    }
}
