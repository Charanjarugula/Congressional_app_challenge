import Foundation

/// 21 bits: 7 days × 3 blocks. Bit index = day * 3 + block, Monday = 0.
/// Stored as a single integer so it round-trips to the backend unchanged.
struct AvailabilityMask: Codable, Equatable, Hashable {
    enum Block: Int, CaseIterable, Identifiable {
        case morning, afternoon, evening

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .morning: "Morning"
            case .afternoon: "Afternoon"
            case .evening: "Evening"
            }
        }

        var hoursLabel: String {
            switch self {
            case .morning: "7–11"
            case .afternoon: "12–4"
            case .evening: "5–9"
            }
        }

        /// 24-hour start and end used when comparing against calendar events.
        var hourRange: (start: Int, end: Int) {
            switch self {
            case .morning: (7, 11)
            case .afternoon: (12, 16)
            case .evening: (17, 21)
            }
        }
    }

    /// The grid cell a moment falls in (Monday = 0), or nil outside the three blocks.
    static func slot(for date: Date, calendar: Calendar = .current) -> (day: Int, block: Block)? {
        let hour = calendar.component(.hour, from: date)
        guard let block = Block.allCases.first(where: { hour >= $0.hourRange.start && hour < $0.hourRange.end }) else { return nil }
        return ((calendar.component(.weekday, from: date) + 5) % 7, block)
    }

    static let dayLetters = ["M", "T", "W", "T", "F", "S", "S"]
    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var rawValue: Int32 = 0

    static func bit(day: Int, block: Block) -> Int32 {
        1 << Int32(day * 3 + block.rawValue)
    }

    func contains(day: Int, block: Block) -> Bool {
        rawValue & Self.bit(day: day, block: block) != 0
    }

    mutating func insert(day: Int, block: Block) {
        rawValue |= Self.bit(day: day, block: block)
    }

    mutating func toggle(day: Int, block: Block) {
        rawValue ^= Self.bit(day: day, block: block)
    }

    func hasAny(day: Int) -> Bool {
        Block.allCases.contains { contains(day: day, block: $0) }
    }

    var count: Int {
        rawValue.nonzeroBitCount
    }

    var isEmpty: Bool {
        rawValue == 0
    }

    /// "4 blocks a week · about 2 hits"
    var summary: String {
        let blocks = count
        let hits = Int((Double(blocks) / 2).rounded())
        let blockWord = blocks == 1 ? "block" : "blocks"
        let hitWord = hits == 1 ? "hit" : "hits"
        return "\(blocks) \(blockWord) a week · about \(hits) \(hitWord)"
    }

    /// Short description for settings rows, e.g. "Tue · Thu eve, weekends".
    var shortDescription: String {
        guard !isEmpty else { return "Not set" }
        let weekendFull = (5...6).allSatisfy { day in Block.allCases.allSatisfy { contains(day: day, block: $0) } }
        var parts: [String] = []
        for day in 0..<(weekendFull ? 5 : 7) where hasAny(day: day) {
            let blocks = Block.allCases.filter { contains(day: day, block: $0) }
            if blocks.count == Block.allCases.count {
                parts.append(Self.dayNames[day])
            } else {
                let suffix = blocks.map { block -> String in
                    switch block {
                    case .morning: "am"
                    case .afternoon: "pm"
                    case .evening: "eve"
                    }
                }.joined(separator: "/")
                parts.append("\(Self.dayNames[day]) \(suffix)")
            }
        }
        if weekendFull { parts.append("weekends") }
        return parts.joined(separator: ", ")
    }
}
