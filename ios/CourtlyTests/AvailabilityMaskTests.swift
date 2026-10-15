import XCTest
@testable import Courtly

/// Records the 7 × 3 availability grid: bit layout, the labels it renders, and which cell a moment falls in.
final class AvailabilityMaskTests: XCTestCase {
    func testBitLayoutIsDayTimesThreePlusBlock() {
        XCTAssertEqual(AvailabilityMask.bit(day: 0, block: .morning), 1)
        XCTAssertEqual(AvailabilityMask.bit(day: 0, block: .evening), 4)
        XCTAssertEqual(AvailabilityMask.bit(day: 1, block: .morning), 8)
        XCTAssertEqual(AvailabilityMask.bit(day: 6, block: .evening), 1 << 20)
    }

    func testInsertToggleAndCount() {
        var mask = AvailabilityMask()
        XCTAssertTrue(mask.isEmpty)
        mask.insert(day: 1, block: .evening)
        mask.insert(day: 1, block: .evening)
        XCTAssertTrue(mask.contains(day: 1, block: .evening))
        XCTAssertTrue(mask.hasAny(day: 1))
        XCTAssertFalse(mask.hasAny(day: 2))
        XCTAssertEqual(mask.count, 1)
        mask.toggle(day: 1, block: .evening)
        XCTAssertTrue(mask.isEmpty)
        XCTAssertEqual(AvailabilityMask(rawValue: 0b111).count, 3)
    }

    func testSummaryCountsBlocksAndHalvesThemIntoHits() {
        XCTAssertEqual(AvailabilityMask().summary, "0 blocks a week · about 0 hits")
        XCTAssertEqual(AvailabilityMask(rawValue: 0b1).summary, "1 block a week · about 1 hit")
        XCTAssertEqual(AvailabilityMask(rawValue: 0b111).summary, "3 blocks a week · about 2 hits")
        XCTAssertEqual(AvailabilityMask(rawValue: 0b1111).summary, "4 blocks a week · about 2 hits")
    }

    func testShortDescription() {
        XCTAssertEqual(AvailabilityMask().shortDescription, "Not set")

        var tuesday = AvailabilityMask()
        for block in AvailabilityMask.Block.allCases { tuesday.insert(day: 1, block: block) }
        XCTAssertEqual(tuesday.shortDescription, "Tue")

        var mixed = AvailabilityMask()
        mixed.insert(day: 0, block: .morning)
        mixed.insert(day: 0, block: .afternoon)
        mixed.insert(day: 3, block: .evening)
        XCTAssertEqual(mixed.shortDescription, "Mon am/pm, Thu eve")

        var weekends = AvailabilityMask()
        weekends.insert(day: 1, block: .evening)
        for day in 5...6 { for block in AvailabilityMask.Block.allCases { weekends.insert(day: day, block: block) } }
        XCTAssertEqual(weekends.shortDescription, "Tue eve, weekends")

        var saturdayMorning = AvailabilityMask()
        saturdayMorning.insert(day: 5, block: .morning)
        XCTAssertEqual(saturdayMorning.shortDescription, "Sat am")

        let everything = AvailabilityMask(rawValue: (1 << 21) - 1)
        XCTAssertEqual(everything.shortDescription, "Mon, Tue, Wed, Thu, Fri, weekends")
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func moment(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        // October 2026: the 18th is a Sunday, the 19th a Monday.
        utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testSlotMapsHoursToBlocksWithMondayFirst() {
        XCTAssertTrue(AvailabilityMask.slot(for: moment(19, 8), calendar: utc).map { $0.day == 0 && $0.block == .morning } ?? false)
        XCTAssertTrue(AvailabilityMask.slot(for: moment(19, 12), calendar: utc).map { $0.day == 0 && $0.block == .afternoon } ?? false)
        XCTAssertTrue(AvailabilityMask.slot(for: moment(18, 20, 59), calendar: utc).map { $0.day == 6 && $0.block == .evening } ?? false)
    }

    func testMomentsBetweenBlocksHaveNoSlot() {
        XCTAssertNil(AvailabilityMask.slot(for: moment(19, 6, 59), calendar: utc))
        XCTAssertNil(AvailabilityMask.slot(for: moment(19, 11, 30), calendar: utc))
        XCTAssertNil(AvailabilityMask.slot(for: moment(19, 16), calendar: utc))
        XCTAssertNil(AvailabilityMask.slot(for: moment(19, 21), calendar: utc))
    }
}
