import SwiftUI

/// 08 · Location and 09 · Location confirmed. Type-ahead search or device location, then travel radius.
struct LocationView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var query = ""
    @State private var isLocating = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    // @StateObject builds these once per screen; @State would build them on every re-init of the view.
    @StateObject private var locationService = LocationService()
    @StateObject private var completer = PlaceSearchCompleter()
    @FocusState private var isEditing: Bool

    var body: some View {
        OnboardingStepView(
            progress: 0.7,
            title: "Where do you play?",
            subtitle: "We’ll match you with players and courts nearby.",
            appearance: .courtsideBlue
        ) {
            if let area = draft.homeArea {
                confirmedField(area)
                    .padding(.top, 28)
                Text("Other players see your area, never your exact location.")
                    .font(CourtlyFont.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 10)
                SectionLabel(title: "How far will you travel for a hit?", color: .white)
                    .padding(.top, 32)
                    .padding(.bottom, 10)
                HStack(spacing: 8) {
                    ForEach(TravelRadius.allCases) { radius in
                        radiusChip(radius)
                    }
                }
            } else {
                searchField
                    .padding(.top, 28)
                if !completer.suggestions.isEmpty {
                    suggestionList
                        .padding(.top, 8)
                }
                if let errorMessage {
                    OnboardingErrorCaption(text: errorMessage)
                        .padding(.top, 10)
                }
            }
        } footer: {
            if draft.homeArea != nil {
                PrimaryButton(title: "Continue", style: .lime, compact: true, action: onContinue)
            } else {
                VStack(spacing: 4) {
                    PrimaryButton(title: "Use my location", style: .lime, compact: true, isLoading: isLocating, action: useMyLocation)
                    TextActionButton(title: "Enter it manually", color: .white) { isEditing = true }
                }
            }
        }
        .onChange(of: query) { _, newValue in
            errorMessage = nil
            completer.update(query: newValue)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        FieldBox(fill: .white, cornerRadius: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CourtlyColor.secondary)
            TextField("City or ZIP code", text: $query, prompt: Text("City or ZIP code").foregroundStyle(CourtlyColor.secondary))
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.ink)
                .textContentType(.addressCity)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isEditing)
                .onSubmit(submitQuery)
            if isSearching {
                ProgressView().tint(CourtlyColor.secondary)
            } else if !query.isEmpty {
                Button {
                    query = ""
                    completer.clear()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(CourtlyColor.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
    }

    /// Suggestions appear under the field as the player types, like Maps.
    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(completer.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index > 0 {
                    HairlineSeparator()
                        .padding(.leading, 18)
                }
                Button {
                    select(suggestion)
                } label: {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(suggestion.title)
                            .font(CourtlyFont.body)
                            .foregroundStyle(CourtlyColor.ink)
                        if !suggestion.subtitle.isEmpty {
                            Text(suggestion.subtitle)
                                .font(CourtlyFont.caption)
                                .foregroundStyle(CourtlyColor.secondary)
                        }
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                .strokeBorder(CourtlyColor.separator, lineWidth: 1)
        )
    }

    private func confirmedField(_ area: HomeArea) -> some View {
        FieldBox(fill: .white, cornerRadius: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CourtlyColor.blue)
            Text(area.label)
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(CourtlyColor.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            LinkButton(title: "Change") {
                draft.homeArea = nil
                query = ""
                errorMessage = nil
                completer.clear()
            }
        }
    }

    private func radiusChip(_ radius: TravelRadius) -> some View {
        let isSelected = draft.radius == radius
        return Button {
            draft.radius = radius
        } label: {
            Text(radius.title)
                .font(CourtlyFont.secondarySemibold)
                .foregroundStyle(CourtlyColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? CourtlyColor.lime : .white)
                )
        }
        .buttonStyle(PressableButtonStyle())
    }

    // MARK: - Actions

    private func useMyLocation() {
        guard !isLocating else { return }
        isLocating = true
        errorMessage = nil
        Task { @MainActor in
            do {
                draft.homeArea = try await locationService.currentArea()
                completer.clear()
            } catch LocationService.LocationError.denied {
                errorMessage = "Location is off for Courtly. Enter a city or ZIP code instead."
            } catch {
                errorMessage = "Couldn’t get your location. Enter a city or ZIP code instead."
            }
            isLocating = false
        }
    }

    /// Return key: take the top suggestion if there is one, otherwise geocode what was typed.
    private func submitQuery() {
        if let first = completer.suggestions.first {
            select(first)
        } else {
            lookUpTypedQuery()
        }
    }

    private func select(_ suggestion: PlaceSearchCompleter.Suggestion) {
        guard !isSearching else { return }
        isSearching = true
        isEditing = false
        errorMessage = nil
        Task { @MainActor in
            do {
                draft.homeArea = try await PlaceSearchCompleter.resolve(suggestion.completion)
                completer.clear()
            } catch {
                errorMessage = "Couldn’t find that place. Try a ZIP code."
            }
            isSearching = false
        }
    }

    private func lookUpTypedQuery() {
        guard !isSearching, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        isEditing = false
        errorMessage = nil
        Task { @MainActor in
            do {
                draft.homeArea = try await LocationService.area(matching: query)
                completer.clear()
            } catch {
                errorMessage = "Couldn’t find that place. Try a ZIP code."
            }
            isSearching = false
        }
    }
}
