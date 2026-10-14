import EventKit
import Foundation

/// Reads free/busy from the device calendar. Event titles never leave the device;
/// the only output is a 7×3 mask of blocks that are already busy this coming week.
final class CalendarService {
    enum CalendarError: Error {
        case denied
    }

    private let store = EKEventStore()

    func connect() async throws -> (connection: CalendarConnection, busy: AvailabilityMask) {
        let granted = try await store.requestFullAccessToEvents()
        guard granted else { throw CalendarError.denied }
        let calendarCount = store.calendars(for: .event).count
        let detail = calendarCount == 1 ? "Synced · 1 calendar" : "Synced · \(calendarCount) calendars"
        return (CalendarConnection(provider: .apple, detail: detail), busyMaskForComingWeek())
    }

    /// A block is busy when timed events overlap it by 45 minutes or more.
    func busyMaskForComingWeek() -> AvailabilityMask {
        var mask = AvailabilityMask()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: .now)
        guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return mask }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).filter { !$0.isAllDay }

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let weekday = calendar.component(.weekday, from: day) // 1 = Sunday
            let column = (weekday + 5) % 7 // Monday = 0
            for block in AvailabilityMask.Block.allCases {
                let hours = block.hourRange
                guard
                    let blockStart = calendar.date(bySettingHour: hours.start, minute: 0, second: 0, of: day),
                    let blockEnd = calendar.date(bySettingHour: hours.end, minute: 0, second: 0, of: day)
                else { continue }
                let overlap = events.reduce(0.0) { total, event in
                    let overlapStart = max(event.startDate, blockStart)
                    let overlapEnd = min(event.endDate, blockEnd)
                    return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
                }
                if overlap >= 45 * 60 {
                    mask.insert(day: column, block: block)
                }
            }
        }
        return mask
    }
}
