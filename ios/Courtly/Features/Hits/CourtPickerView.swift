import MapKit
import SwiftUI

/// Search places or full street addresses, then confirm the exact location and court details.
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
    @State private var chosenPlace: PlaceResult?
    @State private var searchError: String?
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FieldBox(fill: .white, cornerRadius: 22) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(CourtlyColor.secondary)
                        TextField("Address, court, or place name", text: $query)
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
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(CourtlyColor.surface.ignoresSafeArea())
            .navigationTitle("Where")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelCourtSearch")
                        .disabled(addingID != nil)   // a court is being added; closing now would hand it back to a closed sheet
                }
            }
            .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
            .onDisappear { searchTask?.cancel() }
            .sheet(item: $chosenPlace) { place in
                CourtLocationConfirmation(place: place) { name, surface, lights in
                    try await save(place, name: name, surface: surface, lights: lights)
                }
            }
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
            QuietCard(title: "No courts near you yet", detail: "Search a full address or place name to add a court.")
        } else {
            CardRows(items: courts, radius: 22) { court in
                Button {
                    chosenPlace = PlaceResult(court: court)
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(court.name)
                                .font(CourtlyFont.bodySemibold)
                                .foregroundStyle(CourtlyColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(courtDetail(court))
                                .font(CourtlyFont.secondary)
                                .foregroundStyle(CourtlyColor.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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
            Text("Search by street address, court, or park name. Include a city for more precise results.")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        SectionHeader(title: isSearching ? "Searching…" : "Results")
        if let searchError {
            QuietCard(title: "Couldn’t search places", detail: searchError)
            Button("Try again") { scheduleSearch(query) }.padding(.top, 12)
        } else if results.isEmpty {
            if !isSearching {
                QuietCard(title: "No places found", detail: "Try a full street address with its city, or a court name.")
            }
        } else {
            CardRows(items: results, radius: 22) { place in
                Button {
                    chosenPlace = place
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(CourtlyColor.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.name)
                                .font(CourtlyFont.bodySemibold)
                                .foregroundStyle(CourtlyColor.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = place.detail {
                                Text(detail)
                                    .font(CourtlyFont.secondary)
                                    .foregroundStyle(CourtlyColor.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        if addingID == place.id {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Review")
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
        if let address = court.address ?? court.city { parts.append(address) }
        if let miles = court.miles { parts.append(HitFormatting.miles(miles)) }
        if let played = court.playedCount, played > 0 { parts.append(played == 1 ? "Played here once" : "Played here \(played) times") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Search

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        searchError = nil
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
            do {
                let response = try await MKLocalSearch(request: request).start()
                guard !Task.isCancelled else { return }
                results = response.mapItems.compactMap(PlaceResult.init)
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                searchError = "Check your connection and try again."
            }
            isSearching = false
        }
    }

    private func save(_ place: PlaceResult, name: String, surface: String?, lights: Bool?) async throws {
        if let existing = place.existingCourt, existing.surface == surface, existing.lights == lights {
            onPick(existing)
            chosenPlace = nil
            dismiss()
            return
        }
        guard addingID == nil else { return }
        addingID = place.id
        defer { addingID = nil }
        // Resolve the place's zone, never silently schedule a remote court in the player's zone.
        var zone = place.timeZone
        if zone == nil {
            let placemarks = try await CLGeocoder().reverseGeocodeLocation(
                CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude))
            zone = placemarks.first?.timeZone?.identifier
        }
        guard let zone else {
            throw NSError(domain: "CourtLocation", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "We couldn’t determine this location’s time zone. Try searching a more complete address."])
        }
        let court = try await API.Courts.add(
            name: name, address: place.address, city: place.city,
            latitude: place.coordinate.latitude, longitude: place.coordinate.longitude,
            applePlaceID: place.appleID, timeZone: zone, surface: surface, lights: lights)
        onPick(court)
        chosenPlace = nil
        dismiss()
    }

}

/// What the picker needs from an Apple Maps result.
private struct PlaceResult: Identifiable {
    let name: String
    let address: String?
    let city: String?
    let coordinate: CLLocationCoordinate2D
    let appleID: String?
    let timeZone: String?
    var existingCourt: Court? = nil

    init(court: Court) {
        name = court.name
        address = court.address
        city = court.city
        coordinate = court.coordinate
        appleID = nil
        timeZone = court.timeZone
        existingCourt = court
    }

    var id: String { "\(name)|\(coordinate.latitude),\(coordinate.longitude)" }

    var detail: String? {
        address ?? city
    }

    init?(item: MKMapItem) {
        coordinate = PlaceDetails.coordinate(of: item)
        address = PlaceDetails.street(of: item)
        city = PlaceDetails.city(of: item)
        // A plain address has no name of its own; the street stands in.
        guard let name = (item.name ?? address)?.nilIfEmpty else { return nil }
        self.name = name
        timeZone = item.timeZone?.identifier
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
        let street = [placemark.subThoroughfare, placemark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return [street.nilIfEmpty, placemark.locality, placemark.administrativeArea,
                placemark.postalCode, placemark.country].compactMap { $0 }.joined(separator: ", ").nilIfEmpty
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

/// Address and map stay tied to the selected search result; only court facts are editable.
private struct CourtLocationConfirmation: View {
    let place: PlaceResult
    let onSave: (String, String?, Bool?) async throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var surface = ""
    @State private var lighting = "unknown"
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: place.coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003)))) {
                        Marker(place.name, coordinate: place.coordinate).tint(CourtlyColor.blue)
                    }
                    .frame(height: 190)
                    .accessibilityLabel("Selected location: \(place.detail ?? place.name)")
                    Text(place.detail ?? place.name).textSelection(.enabled)
                } header: { Text("Confirm location") }
                  footer: { Text("Check the pin and address. Go back to search if this isn’t your court.") }
                Section("Court details") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Court name").font(.caption).foregroundStyle(CourtlyColor.secondary)
                        TextField("Court name", text: $name)
                            .accessibilityIdentifier("courtName")
                            .disabled(place.existingCourt != nil)
                    }
                    Picker("Surface", selection: $surface) {
                        Text("Not sure").tag("")
                        Text("Hard").tag("hard")
                        Text("Clay").tag("clay")
                        Text("Grass").tag("grass")
                        Text("Carpet").tag("carpet")
                        Text("Other").tag("other")
                    }
                    .disabled(place.existingCourt?.surface != nil)
                    Picker("Lights", selection: $lighting) {
                        Text("Not sure").tag("unknown")
                        Text("Yes").tag("yes")
                        Text("No").tag("no")
                    }
                    .disabled(place.existingCourt?.lights != nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(CourtlyColor.surface)
            .navigationTitle("Use this court")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ActionButton(title: isSaving ? "Saving…" : "Use this court", style: .lime) {
                    guard !isSaving else { return }
                    isSaving = true
                    Task { @MainActor in
                        do {
                            try await onSave(name.trimmingCharacters(in: .whitespacesAndNewlines),
                                             surface.isEmpty ? nil : surface,
                                             lighting == "unknown" ? nil : lighting == "yes")
                        } catch { errorMessage = error.localizedDescription }
                        isSaving = false
                    }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(20)
                .background(CourtlyColor.surface)
            }
            .onAppear {
                name = place.name
                surface = place.existingCourt?.surface ?? ""
                lighting = place.existingCourt?.lights.map { $0 ? "yes" : "no" } ?? "unknown"
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage, title: "Couldn’t use this court")
        }
        .tint(CourtlyColor.blue)
    }
}
