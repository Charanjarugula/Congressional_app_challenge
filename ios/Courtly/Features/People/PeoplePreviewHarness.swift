#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Read-only fixtures for request grouping and compact/large-text layout checks.
struct PeoplePreviewHarness: View {
    @State private var inbox = InboxStore(previewRequests: Self.requests)

    var body: some View {
        NavigationStack { FriendRequestsView() }
            .environment(inbox)
    }

    private static var requests: FriendRequests {
        let json = """
        {"incoming":[
          {"id":"00000000-0000-0000-0000-000000000001","firstName":"Ana","lastInitial":"M","level":"intermediate","areaLabel":"Wellington","hitsPlayed":4,"formats":[],"mutualFriends":["Jordan","Luis"]},
          {"id":"00000000-0000-0000-0000-000000000002","firstName":"Alexandria","lastInitial":"G","level":"intermediate","areaLabel":"Palm Beach Gardens","hitsPlayed":2,"formats":[],"mutualFriends":[]}
        ],"outgoing":[
          {"id":"00000000-0000-0000-0000-000000000003","firstName":"Daniel","lastInitial":"K","level":"advanced","areaLabel":"Wellington","hitsPlayed":7,"formats":[],"mutualFriends":[]}
        ]}
        """
        return try! JSONDecoder().decode(FriendRequests.self, from: Data(json.utf8))
    }
}
#endif
