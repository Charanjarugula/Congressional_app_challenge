import Foundation
import MapKit
import Observation

/// Type-ahead place suggestions backed by MapKit, kept to the United States.
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
    /// The lower 48 plus Alaska and Hawaii's latitudes; it only biases MapKit, the filter below does the rest.
    private static let unitedStates = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 70)
    )

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .address
        completer.region = Self.unitedStates
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
        guard let item = response.mapItems.first(where: { $0.placemark.isoCountryCode == "US" }) else {
            throw LocationService.LocationError.notFound
        }
        return await LocationService.coarsened(
            HomeArea(placemark: item.placemark, fallback: item.placemark.coordinate)
        )
    }

    // MARK: - MKLocalSearchCompleterDelegate

    /// The region only biases MapKit; it still offers namesakes abroad, so those are dropped here.
    private static func isInUnitedStates(_ result: MKLocalSearchCompletion) -> Bool {
        result.subtitle.isEmpty || result.subtitle.contains("United States")
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.filter { Self.isCityOrZip($0.title) && Self.isInUnitedStates($0) }.prefix(6).map { result in
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
