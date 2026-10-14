import CoreLocation
import Foundation

/// One-shot location lookup that turns a coordinate or a typed city/ZIP into a `HomeArea`.
/// Every result goes through `coarsened(_:)`, so the stored point is the centroid of the
/// player's ZIP (or city), never the device fix or a street address.
final class LocationService: NSObject, CLLocationManagerDelegate {
    enum LocationError: Error {
        case denied, unavailable, notFound
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentArea() async throws -> HomeArea {
        let status = await requestAuthorizationIfNeeded()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw LocationError.denied
        }
        let location = try await requestLocation()
        return try await Self.area(for: location)
    }

    static func area(for location: CLLocation) async throws -> HomeArea {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        guard let placemark = placemarks.first else { throw LocationError.notFound }
        return await coarsened(HomeArea(placemark: placemark, fallback: location.coordinate))
    }

    /// Replaces a precise point with the centroid of the area's ZIP, or its city when there is
    /// no ZIP. Falls back to rounding to about 1 km if the lookup fails.
    static func coarsened(_ area: HomeArea) async -> HomeArea {
        // A ZIP is replaced by its centroid; a city keeps its own point, rounded. Looking a city label up
        // again could land on a namesake elsewhere, which is how a Wellington once ended up in New Zealand.
        if let zip = area.zip,
           let placemark = try? await CLGeocoder().geocodeAddressString("\(zip), United States", in: serviceRegion)
               .first(where: { $0.isoCountryCode == "US" }),
           let location = placemark.location {
            return HomeArea(
                label: area.label,
                zip: area.zip,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
        return HomeArea(
            label: area.label,
            zip: area.zip,
            latitude: (area.latitude * 100).rounded() / 100,
            longitude: (area.longitude * 100).rounded() / 100
        )
    }

    /// Courtly runs in the United States; a lookup is steered towards Palm Beach County and anything
    /// abroad is dropped, so "Wellington" is Wellington, FL and never the one in New Zealand.
    static let serviceRegion = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: 26.65, longitude: -80.2), radius: 150_000, identifier: "palm-beach"
    )

    static func area(matching query: String) async throws -> HomeArea {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocationError.notFound }
        let looksLikeZip = text.count == 5 && text.allSatisfy(\.isNumber)
        let placemarks = try await CLGeocoder().geocodeAddressString(looksLikeZip ? "\(text), United States" : text, in: serviceRegion)
        guard let placemark = placemarks.first(where: { $0.isoCountryCode == "US" }), let location = placemark.location else {
            throw LocationError.notFound
        }
        return await coarsened(HomeArea(placemark: placemark, fallback: location.coordinate))
    }

    // MARK: - Private

    private func requestAuthorizationIfNeeded() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            manager.requestWhenInUseAuthorization()
        }
    }

    private func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        authorizationContinuation?.resume(returning: manager.authorizationStatus)
        authorizationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.last {
            locationContinuation?.resume(returning: location)
        } else {
            locationContinuation?.resume(throwing: LocationError.unavailable)
        }
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}

extension HomeArea {
    init(placemark: CLPlacemark, fallback: CLLocationCoordinate2D) {
        let city = placemark.locality ?? placemark.subAdministrativeArea ?? placemark.name ?? "Your area"
        let region = placemark.administrativeArea
        let coordinate = placemark.location?.coordinate ?? fallback
        self.init(
            label: region.map { "\(city), \($0)" } ?? city,
            zip: placemark.postalCode,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}

/// Lets the Area sheet hold one instance for its lifetime with @StateObject; the sheet only calls it, so nothing here is published.
extension LocationService: ObservableObject {}
