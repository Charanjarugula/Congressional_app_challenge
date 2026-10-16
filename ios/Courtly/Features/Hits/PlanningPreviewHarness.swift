#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Exercises the real form without posting a hit or completing authentication.
struct PlanningPreviewHarness: View {
    @State private var hits = HitsStore(account: nil)
    @State private var showsPlan = false

    var body: some View {
        Button("Open plan") { showsPlan = true }
            .sheet(isPresented: $showsPlan) { PlanHitView { _ in } }
            .environment(hits)
    }
}
#endif
