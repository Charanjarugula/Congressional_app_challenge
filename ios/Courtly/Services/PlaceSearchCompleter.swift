import Foundation
import MapKit
import Observation

/// Type-ahead place suggestions backed by MapKit, biased to Palm Beach County.
/// Tapping a suggestion resolves it to a `HomeArea` (city label, ZIP when known, centroid).
@Observable
final class PlaceSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    struct Suggestion: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        let completion: MKLocalSearchCompletion

        static func == (lhs: Suggestion, rhs: Suggestion) -> Bool {
            lhs.id == rhs.id
        }
    }

    private(set) var suggestions: [Suggestion] = []

    private let completer = MKLocalSearchCompleter()
    private static let palmBeachCounty = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 26.65, longitude: -80.2),
        latitudinalMeters: 120_000,
        longitudinalMeters: 120_000
    )

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = Self.palmBeachCounty
        if #available(iOS 18.0, *) {
            completer.addressFilter = MKAddressFilter(including: [.locality, .subLocality, .postalCode])
        }
    }

    /// Street addresses start with a house number; ZIP codes are five digits. Keep cities and ZIPs.
    private static func isCityOrZip(_ title: String) -> Bool {
        guard let first = title.first, first.isNumber else { return true }
        let token = title.prefix { $0.isNumber }
        return token.count == 5 && title.count <= 5 + 2
    }

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            completer.cancel()
            suggestions = []
            return
        }
        completer.queryFragment = trimmed
    }

    func clear() {
        completer.cancel()
        suggestions = []
    }

    static func resolve(_ completion: MKLocalSearchCompletion) async throws -> HomeArea {
        let response = try await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start()
        guard let item = response.mapItems.first else {
            throw LocationService.LocationError.notFound
        }
        return await LocationService.coarsened(
            HomeArea(placemark: item.placemark, fallback: item.placemark.coordinate)
        )
    }

    // MARK: - MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.filter { Self.isCityOrZip($0.title) }.prefix(6).map { result in
            Suggestion(
                id: result.title + "|" + result.subtitle,
                title: result.title,
                subtitle: result.subtitle,
                completion: result
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        suggestions = []
    }
}

/// Lets screens hold one instance with @StateObject; change tracking still comes from @Observable.
extension PlaceSearchCompleter: ObservableObject {}
