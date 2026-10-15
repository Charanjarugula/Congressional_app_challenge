import SwiftUI

struct AreaSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var zip = ""
    @State private var area: HomeArea?
    @State private var radius: TravelRadius = .ten
    @State private var isLookingUp = false
    @State private var lookupTask: Task<Void, Never>?
    @StateObject private var locationService = LocationService()
    @State private var skipNextLookup = false
    @State private var seeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Area", canSave: area != nil, isSaving: isSaving, onSave: save) {
            SectionLabel(title: "ZIP code")
                .padding(.bottom, 8)
            HStack(spacing: 12) {
                TextField("33411", text: $zip)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .keyboardType(.numberPad)
                Spacer(minLength: 0)
                if isLookingUp {
                    ProgressView().controlSize(.small)
                } else if let area {
                    Text(area.label.components(separatedBy: ",").first ?? area.label)
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(CourtlyColor.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous).fill(CourtlyColor.card))
            LinkButton(title: "Use my location") { useLocation() }
                .padding(.top, 10)
                .padding(.leading, 4)

            SectionLabel(title: "Show hits within")
                .padding(.top, 18)
                .padding(.bottom, 8)
            HStack(spacing: 8) {
                ForEach(TravelRadius.allCases) { option in
                    Button {
                        radius = option
                    } label: {
                        Text(option.title)
                            .font(CourtlyFont.secondarySemibold)
                            .foregroundStyle(radius == option ? CourtlyColor.blue : CourtlyColor.ink)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(radius == option ? CourtlyColor.blueTint : CourtlyColor.card)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .onAppear {
            guard !seeded, let profile = session.profile else { return }
            seeded = true
            area = profile.homeArea
            zip = profile.zip ?? ""
            radius = profile.radius
        }
        .onChange(of: zip) { _, newValue in
            let digits = String(newValue.filter(\.isNumber).prefix(5))
            if digits != newValue { zip = digits; return }   // a ZIP is five digits, nothing else gets in
            lookUp(digits)
        }
        .errorAlert($errorMessage)
    }

    private func lookUp(_ text: String) {
        lookupTask?.cancel()
        isLookingUp = false
        if skipNextLookup {
            skipNextLookup = false
            return
        }
        let digits = text.filter(\.isNumber)
        if digits != text { zip = digits; return }
        if area?.zip == digits { return }
        area = nil
        guard digits.count == 5 else { return }
        isLookingUp = true
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = try? await LocationService.area(matching: digits)
            guard !Task.isCancelled else { return }
            area = found
            isLookingUp = false
            if found == nil { errorMessage = "We couldn’t find that ZIP code." }
        }
    }

    private func useLocation() {
        guard !isLookingUp else { return }
        isLookingUp = true
        Task { @MainActor in
            do {
                let found = try await locationService.currentArea()
                skipNextLookup = (found.zip ?? "") != zip
                zip = found.zip ?? ""
                area = found
            } catch {
                errorMessage = "Location is off for Courtly. Type your ZIP code instead."
            }
            isLookingUp = false
        }
    }

    private func save() {
        guard let area else { return }
        isSaving = true
        Task { @MainActor in
            do {
                var patch: [String: Any] = [
                    "area_label": area.label,
                    "home_lat": area.latitude,
                    "home_lng": area.longitude,
                    "radius_mi": radius.rawValue,
                ]
                patch["zip"] = area.zip ?? NSNull()
                try await session.updateProfile(patch)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
