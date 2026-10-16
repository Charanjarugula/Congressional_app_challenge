#if DEBUG && targetEnvironment(simulator)
import SwiftUI

struct HitsPreviewHarness: View {
    @State private var hits = HitsStore(account: nil)
    private let states = ["Open", "Host", "Pending", "Invited", "Confirmed", "Cancelled", "Played"]
    var body: some View {
        NavigationStack {
            List(states, id: \.self) { state in
                NavigationLink(state) { HitDetailView(preview: example(state)) }
            }
            .navigationTitle("Hit state checks")
        }
        .environment(hits)
    }

    private func example(_ state: String) -> Hit {
        var hit = ExplorePreviewHarness.exampleHit
        switch state {
        case "Host": hit.viewer.isHost = true
        case "Pending": hit.viewer.request = .init(id: UUID(), status: .pending, seen: true)
        case "Invited": hit.viewer.invite = .init(id: UUID(), status: .open, expiresAt: .now.addingTimeInterval(3600))
        case "Confirmed": hit.status = .confirmed; hit.spotsOpen = 0; hit.viewer.isPlayer = true; hit.chatId = UUID()
        case "Cancelled": hit.status = .cancelled
        case "Played": hit.status = .played; hit.viewer.isPlayer = true; hit.startsAt = .now.addingTimeInterval(-86400); hit.chatId = UUID()
        default: break
        }
        return hit
    }
}
#endif
