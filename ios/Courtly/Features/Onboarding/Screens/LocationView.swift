import SwiftUI

/// 08 · Location and 09 · Location confirmed. Search field or device location, then travel radius.
struct LocationView: View {
    @Bindable var draft: OnboardingDraft
    let onContinue: () -> Void

    @State private var query = ""
    @State private var isLocating = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var locationService = LocationService()
    @FocusState private var isEditing: Bool

    var body: some View {
        OnboardingStepView(
            progress: 0.7,
            title: "Where do you play?",
            subtitle: "We’ll match you with players and courts nearby."
        ) {
            if let area = draft.homeArea {
                confirmedField(area)
                    .padding(.top, 28)
                Text("Other players see your area, never your exact location.")
                    .font(CourtlyFont.caption)
                    .foregroundStyle(CourtlyColor.secondary)
                    .padding(.top, 10)
                SectionLabel(title: "How far will you travel for a hit?")
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
                if let errorMessage {
                    Text(errorMessage)
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.red)
                        .padding(.top, 10)
                }
            }
        } footer: {
            if draft.homeArea != nil {
                PrimaryButton(title: "Continue", action: onContinue)
            } else {
                VStack(spacing: 4) {
                    PrimaryButton(title: "Use my location", isLoading: isLocating, action: useMyLocation)
                    TextActionButton(title: "Enter it manually") { isEditing = true }
                }
            }
        }
    }

    private var searchField: some View {
        FieldBox {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CourtlyColor.secondary)
            TextField("City or ZIP code", text: $query)
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.ink)
                .textContentType(.postalCode)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isEditing)
                .onSubmit(lookUpQuery)
            if isSearching {
                ProgressView().tint(CourtlyColor.secondary)
            }
        }
    }

    private func confirmedField(_ area: HomeArea) -> some View {
        FieldBox(isHighlighted: true) {
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
                .foregroundStyle(isSelected ? CourtlyColor.blue : CourtlyColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? CourtlyColor.blueTint : CourtlyColor.groupedBackground)
                )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func useMyLocation() {
        guard !isLocating else { return }
        isLocating = true
        errorMessage = nil
        Task { @MainActor in
            do {
                draft.homeArea = try await locationService.currentArea()
            } catch LocationService.LocationError.denied {
                errorMessage = "Location is off for Courtly. Enter a city or ZIP code instead."
            } catch {
                errorMessage = "Couldn’t get your location. Enter a city or ZIP code instead."
            }
            isLocating = false
        }
    }

    private func lookUpQuery() {
        guard !isSearching, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task { @MainActor in
            do {
                draft.homeArea = try await LocationService.area(matching: query)
            } catch {
                errorMessage = "Couldn’t find that place. Try a ZIP code."
            }
            isSearching = false
        }
    }
}
