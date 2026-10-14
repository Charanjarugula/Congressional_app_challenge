import MapKit
import SwiftUI
import UIKit

/// Small static map of the court with a Directions chip that hands off to Apple Maps.
struct CourtMap: View {
    let court: Court
    var height: CGFloat = 120

    var body: some View {
        Map(
            initialPosition: .region(MKCoordinateRegion(center: court.coordinate, latitudinalMeters: 900, longitudinalMeters: 900)),
            interactionModes: []
        ) {
            Annotation("", coordinate: court.coordinate) {
                Circle()
                    .fill(CourtlyColor.blue)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button(action: openDirections) {
                Text("Directions")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CourtlyColor.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.white))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.trailing, 10)
            .padding(.bottom, 8)
        }
    }

    private func openDirections() {
        let name = court.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://maps.apple.com/?daddr=\(court.lat),\(court.lng)&q=\(name)&dirflg=d") else { return }
        UIApplication.shared.open(url)
    }
}
