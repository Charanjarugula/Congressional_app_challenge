import XCTest
@testable import Courtly

final class ExploreFiltersTests: XCTestCase {
    func testDistanceIsUnrestrictedByDefaultIncludingUnknownLocations() {
        let filters = ExploreFilters()
        XCTAssertEqual(filters.activeCount, 0)
        XCTAssertTrue(filters.distance.includes(150))
        XCTAssertTrue(filters.distance.includes(nil))
    }
    func testExplicitDistanceBoundaryAndReset() {
        var filters = ExploreFilters()
        filters.distance = .fifty
        XCTAssertTrue(filters.distance.includes(50))
        XCTAssertFalse(filters.distance.includes(50.1))
        XCTAssertFalse(filters.distance.includes(nil))
        XCTAssertEqual(filters.activeCount, 1)
        filters = ExploreFilters()
        XCTAssertTrue(filters.distance.includes(51))
    }
}
