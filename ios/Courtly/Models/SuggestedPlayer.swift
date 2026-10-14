import Foundation

/// A player shown on the "People to play with" step.
struct SuggestedPlayer: Identifiable, Equatable {
    enum Source {
        case contacts, recommended
    }

    let id: String
    let fullName: String
    let level: PlayerLevel
    let distanceMiles: Int
    let source: Source

    var initials: String {
        let parts = fullName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return String(letters).uppercased()
    }

    var detail: String {
        "\(level.title) · \(distanceMiles) mi"
    }
}

/// Stand-in data until the backend exists. Everything here is replaced by real queries
/// in the backend integration; nothing in this file ships to users.
enum SampleData {
    static let contactsOnCourtly: [SuggestedPlayer] = [
        SuggestedPlayer(id: "sample-jordan", fullName: "Jordan Tate", level: .intermediate, distanceMiles: 3, source: .contacts),
        SuggestedPlayer(id: "sample-alex", fullName: "Alex Okafor", level: .advanced, distanceMiles: 6, source: .contacts),
    ]

    static let recommended: [SuggestedPlayer] = [
        SuggestedPlayer(id: "sample-daniel", fullName: "Daniel K.", level: .intermediate, distanceMiles: 2, source: .recommended),
        SuggestedPlayer(id: "sample-priya", fullName: "Priya S.", level: .intermediate, distanceMiles: 4, source: .recommended),
        SuggestedPlayer(id: "sample-luis", fullName: "Luis M.", level: .intermediate, distanceMiles: 5, source: .recommended),
        SuggestedPlayer(id: "sample-hannah", fullName: "Hannah C.", level: .advanced, distanceMiles: 7, source: .recommended),
    ]
}
