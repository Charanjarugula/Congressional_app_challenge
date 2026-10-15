import MapKit
import SwiftUI

/// Courts near you first; search Apple Maps for a park or tennis center to add one.
struct CourtPickerView: View {
    let courts: [Court]
    let selected: Court?
    let onPick: (Court) -> Void

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var isSearching = false
    @State private var addingID: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FieldBox(isHighlighted: !query.isEmpty) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(CourtlyColor.secondary)
                        TextField("Search courts or parks", text: $query)
                            .font(CourtlyFont.body)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                        if !query.isEmpty {
                            Button {
                                query = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(CourtlyColor.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear search")
                        }
                    }
                    .padding(.top, 8)

                    if trimmedQuery.isEmpty {
                        nearbySection
                    } else {
                        resultsSection
                    }
                }
                .padding(.horizontal, CourtlyMetrics.screenPadding)
                .padding(.bottom, 24)
            }
            .background(CourtlyColor.groupedBackground.ignoresSafeArea())
            .navigationTitle("Where")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(addingID != nil)   // a court is being added; closing now would hand it back to a closed sheet
                }
            }
            .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            .interactiveDismissDisabled(addingID != nil)
            .errorAlert($errorMessage, title: "Couldn’t add that court")
        }
        .preferredColorScheme(.light)
    }

    // MARK: - Sections

    @ViewBuilder
    private var nearbySection: some View {
        SectionHeader(title: "Near you")
        if courts.isEmpty {
            QuietCard(title: "No courts near you yet", detail: "Search for a park or tennis center above to add one.")
        } else {
            CardRows(items: courts) { court in
                Button {
                    onPick(court)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(court.name)
                                .font(CourtlyFont.bodySemibold)
                                .foregroundStyle(CourtlyColor.ink)
                                .lineLimit(1)
                            Text(courtDetail(court))
                                .font(CourtlyFont.secondary)
                                .foregroundStyle(CourtlyColor.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        SelectionMark(isSelected: court.id == selected?.id)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Text("Can’t find it? Search for the park or tennis center above and we’ll add it.")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        SectionHeader(title: isSearching ? "Searching…" : "Results")
        if results.isEmpty {
            if !isSearching {
                QuietCard(title: "No places found", detail: "Try the park or tennis center’s name.")
            }
        } else {
            CardRows(items: results) { place in
                Button {
                    add(place)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(CourtlyColor.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name)
                                .font(CourtlyFont.bodySemibold)
                                .foregroundStyle(CourtlyColor.ink)
                                .lineLimit(1)
                            if let detail = place.detail {
                                Text(detail)
                                    .font(CourtlyFont.secondary)
                                    .foregroundStyle(CourtlyColor.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 8)
                        if addingID == place.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Use")
                                .font(CourtlyFont.secondarySemibold)
                                .foregroundStyle(CourtlyColor.blue)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(CourtlyColor.blueTint))
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(addingID != nil)
            }
        }
    }

    private func courtDetail(_ court: Court) -> String {
        var parts: [String] = []
        if let city = court.city { parts.append(city) }
        if let miles = court.miles { parts.append(HitFormatting.miles(miles)) }
        if let played = court.playedCount, played > 0 { parts.append(played == 1 ? "Played here once" : "Played here \(played) times") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Search

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = [.pointOfInterest, .address]
            if let area = session.profile?.homeArea {
                request.region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: area.latitude, longitude: area.longitude),
                    latitudinalMeters: 80_000, longitudinalMeters: 80_000
                )
            }
            let response = try? await MKLocalSearch(request: request).start()
            guard !Task.isCancelled else { return }
            results = (response?.mapItems ?? []).compactMap(PlaceResult.init)
            isSearching = false
        }
    }

    private func add(_ place: PlaceResult) {
        guard addingID == nil else { return }
        addingID = place.id
        Task { @MainActor in
            do {
                let court = try await API.Courts.add(
                    name: place.name, address: place.address, city: place.city,
                    latitude: place.coordinate.latitude, longitude: place.coordinate.longitude,
                    applePlaceID: place.appleID
                )
                onPick(court)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            addingID = nil
        }
    }
}

/// What the picker needs from an Apple Maps result.
private struct PlaceResult: Identifiable {
    let name: String
    let address: String?
    let city: String?
    let coordinate: CLLocationCoordinate2D
    let appleID: String?

    var id: String { "\(name)|\(coordinate.latitude),\(coordinate.longitude)" }

    var detail: String? {
        [address, city].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
    }

    init?(item: MKMapItem) {
        coordinate = PlaceDetails.coordinate(of: item)
        address = PlaceDetails.street(of: item)
        city = PlaceDetails.city(of: item)
        // A plain address has no name of its own; the street stands in.
        guard let name = (item.name ?? address)?.nilIfEmpty else { return nil }
        self.name = name
        if #available(iOS 18, *) {
            appleID = item.identifier?.rawValue
        } else {
            appleID = nil
        }
    }
}

/// Reads location details through `MKPlacemark`, which iOS 26 replaces with `MKAddress`.
@available(iOS, deprecated: 26.0, message: "Switch to MKMapItem.address once the app targets iOS 26.")
private enum PlaceDetails {
    static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        item.placemark.coordinate
    }

    static func city(of item: MKMapItem) -> String? {
        item.placemark.locality
    }

    static func street(of item: MKMapItem) -> String? {
        let placemark = item.placemark
        return [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ").nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
