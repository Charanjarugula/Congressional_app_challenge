import CoreLocation
import Foundation

/// A public court (`court_json`), with distance and play count when the caller has a home area.
struct Court: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let address: String?
    let city: String?
    let lat: Double
    let lng: Double
    let surface: String?
    let lights: Bool?
    /// IANA zone of the court ("America/New_York"); a hit there reads in this zone.
    var timeZone: String? = nil
    var miles: Double?
    var playedCount: Int?

    /// The court's zone, or the device's when the server didn't say.
    var zone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? .current }

    /// "Wellington" when the city is known, otherwise the court's name.
    var shortName: String { city ?? name }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// "Hard · Lights"
    var detailLine: String? {
        var parts: [String] = []
        if let surface, !surface.isEmpty { parts.append(surface.capitalized) }
        if let lights { parts.append(lights ? "Lights" : "No lights") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
