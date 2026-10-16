#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Isolated simulator checks; never compiled into a device or Release build.
struct RemainingFlowsHarness: View {
    @State private var session = AppSession(previewProfile: Self.profile)
    @State private var inbox = InboxStore(account: nil)
    @State private var hits = HitsStore(account: nil)

    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Settings check") { YouView() }
                NavigationLink("People check") {
                    PeopleView(isActive: false)
                        .environment(InboxStore(previewRequests: .empty, previewChats: [chat(left: false)]))
                }
                NavigationLink("My Hits check") {
                    MyHitsView(onPlan: {})
                        .environment(HitsStore(previewMyHits: Self.exampleHits))
                }
                NavigationLink("Player check") { PlayerProfileView(preview: player) }
                NavigationLink("Group check") { GroupInfoView(preview: chat(left: false)) }
                NavigationLink("Chat check") { ChatThreadView(preview: chat(left: false), messages: messages) }
                NavigationLink("Read-only chat check") { ChatThreadView(preview: chat(left: true), messages: messages) }
            }
            .navigationTitle("Remaining flow checks")
        }
        .environment(session)
        .environment(inbox)
        .environment(hits)
    }

    private static let chatID = UUID(uuidString: "00000000-0000-0000-0000-000000000020")!
    private var other: PlayerCard { ExplorePreviewHarness.exampleHit.host }
    private func chat(left: Bool) -> Chat {
        Chat(id: Self.chatID, type: .group, name: "Evening hitters", hitId: nil,
             members: [Self.profile.card, other], memberCount: 2, lastMessageAt: .now,
             preview: nil, lastMessageType: .text, unreadCount: 0, muted: false,
             friendship: nil, leftAt: left ? .now : nil, hit: nil)
    }
    private var messages: [Message] {
        [Message(id: UUID(), chatId: Self.chatID, sender: other, type: .text,
                 body: "Want to hit tomorrow evening?", clientId: nil, createdAt: .now.addingTimeInterval(-60), invite: nil),
         Message(id: UUID(), chatId: Self.chatID, sender: Self.profile.card, type: .text,
                 body: "Yes! Let’s do 6 at Wellington.", clientId: nil, createdAt: .now, invite: nil)]
    }
    private static var exampleHits: MyHits {
        let upcoming = ExplorePreviewHarness.exampleHit
        var past = ExplorePreviewHarness.exampleHit
        past.status = .played
        past.startsAt = .now.addingTimeInterval(-86400 * 4)
        return MyHits(upcoming: [upcoming], past: [past])
    }

    private var player: PlayerProfile {
        var object = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(other)) as! [String: Any]
        object["relationship"] = "friend"
        object["dmChatId"] = Self.chatID.uuidString
        object["friendCount"] = 12
        object["hitsTogether"] = 2
        object["openHits"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(Self.exampleHits.upcoming))
        return try! JSONDecoder().decode(PlayerProfile.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private static var profile: Profile {
        Profile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!, firstName: "Sam", lastName: "Taylor",
                photoPath: nil, birthday: "1998-01-01", gender: nil, level: .intermediate,
                formats: [.casual, .singles], zip: "33411", areaLabel: "Wellington, FL", homeLat: 26.66, homeLng: -80.24,
                radiusMi: 10, availabilityMask: 0, busyMask: 0, busyMaskWeek: 0, calendarProvider: .none,
                hitVisibility: "anyone", hitsPlayed: 4, coachMarksDone: true, onboardingCompletedAt: .now, blockedCount: 0)
    }
}
#endif
