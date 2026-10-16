import SwiftUI

struct AreaSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var zip = ""
    @State private var area: HomeArea?
    @State private var isLookingUp = false
    @State private var lookupTask: Task<Void, Never>?
    @StateObject private var locationService = LocationService()
    @State private var skipNextLookup = false
    @State private var seeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Area", canSave: area != nil && !isLookingUp, isSaving: isSaving, onSave: save) {
            SectionLabel(title: "City or ZIP code")
                .padding(.bottom, 8)
            HStack(spacing: 12) {
                TextField("City, state or ZIP code", text: $zip)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                    .keyboardType(.default)
                    .submitLabel(.search)
                    .onSubmit { lookUp(zip) }
                Spacer(minLength: 0)
                if isLookingUp {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 16).fill(CourtlyColor.card))
            if let area {
                Text(area.label)
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
                    .padding(.top, 8)
            }
            LinkButton(title: "Find area") { lookUp(zip) }
                .disabled(isLookingUp || zip.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                .padding(.top, 10)
            LinkButton(title: "Use my location") { useLocation() }
                .padding(.top, 10)
                .padding(.leading, 4)

        }
        .onAppear {
            guard !seeded, let profile = session.profile else { return }
            seeded = true
            area = profile.homeArea
            let initial = profile.zip ?? profile.areaLabel ?? ""
            skipNextLookup = initial != zip
            zip = initial
        }
        .onChange(of: zip) { _, newValue in
            if skipNextLookup { skipNextLookup = false; return }
            lookupTask?.cancel()
            isLookingUp = false
            area = nil
            if newValue.count == 5 && newValue.allSatisfy(\.isNumber) { lookUp(newValue) }
        }
        .onDisappear { lookupTask?.cancel() }

        .errorAlert($errorMessage)
    }

    private func lookUp(_ text: String) {
        lookupTask?.cancel()
        isLookingUp = false
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        area = nil
        guard query.count >= 2 else { return }
        isLookingUp = true
        lookupTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let found = try? await LocationService.area(matching: query)
            guard !Task.isCancelled else { return }
            area = found
            isLookingUp = false
            if found == nil { errorMessage = "We couldn’t find that area. Try a city and state or a ZIP code." }
        }
    }

    private func useLocation() {
        guard !isLookingUp else { return }
        isLookingUp = true
        lookupTask?.cancel()
        lookupTask = Task { @MainActor in
            do {
                let found = try await locationService.currentArea()
                guard !Task.isCancelled else { return }
                skipNextLookup = (found.zip ?? "") != zip
                zip = found.zip ?? ""
                area = found
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Location is off for Courtly. Enter a city and state or ZIP code instead."
            }
            isLookingUp = false
        }
    }

    private func save() {
        guard let area, !isLookingUp, !isSaving else { return }
        isSaving = true
        Task { @MainActor in
            do {
                var patch: [String: Any] = [
                    "area_label": area.label,
                    "home_lat": area.latitude,
                    "home_lng": area.longitude,
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
