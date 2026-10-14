import EventKit
import EventKitUI
import SwiftUI

/// The system "new event" sheet, prefilled with the hit. Saving needs no calendar permission on iOS 17.
struct CalendarEventEditor: UIViewControllerRepresentable {
    let hit: Hit
    let me: UUID?

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store

        let event = EKEvent(eventStore: store)
        let others = hit.others(than: me).map(\.firstName)
        event.title = others.isEmpty ? "Tennis · \(hit.format.title)" : "Tennis with \(others.joined(separator: ", "))"
        event.startDate = hit.startsAt
        event.endDate = hit.endsAt
        event.location = [hit.court.name, hit.court.address, hit.court.city].compactMap { $0 }.joined(separator: ", ")
        event.notes = "\(hit.formatLine)\nPlanned on Courtly"
        event.calendar = store.defaultCalendarForNewEvents
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(dismiss: dismiss)
    }

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        private let dismiss: DismissAction

        init(dismiss: DismissAction) {
            self.dismiss = dismiss
        }

        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            dismiss()
        }
    }
}
