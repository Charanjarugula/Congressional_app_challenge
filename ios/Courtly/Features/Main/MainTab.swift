import SwiftUI

enum MainTab: Int, CaseIterable, Identifiable {
    case play, myHits, people, you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .play: "Play"
        case .myHits: "My Hits"
        case .people: "People"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .play: "figure.tennis"
        case .myHits: "calendar"
        case .people: "bubble.left.and.bubble.right"
        case .you: "person.crop.circle"
        }
    }
}
