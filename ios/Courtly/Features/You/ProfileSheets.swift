import PhotosUI
import SwiftUI
import UIKit

enum ProfileSheet: String, Identifiable {
    case editProfile, availability, level, formats, area

    var id: String { rawValue }
}

/// Grabber, Cancel / title row, scrolling content, Save at the bottom.
struct SheetScaffold<Content: View>: View {
    let title: String
    var saveTitle = "Save"
    var canSave = true
    var isSaving = false
    var detents: Set<PresentationDetent> = [.medium, .large]
    let onSave: () -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(CourtlyColor.placeholder)
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 14)
            ZStack {
                Text(title)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(CourtlyFont.body)
                        .foregroundStyle(CourtlyColor.blue)
                        .disabled(isSaving)   // a save already under way lands either way, so the sheet stays until it finishes
                    Spacer()
                }
            }
            .frame(height: 36)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.top, 16)
                .padding(.bottom, 16)
            }
            PrimaryButton(title: saveTitle, isEnabled: canSave, isLoading: isSaving, action: onSave)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .presentationDetents(detents)
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .interactiveDismissDisabled(isSaving)
    }
}

/// 52pt white row that turns blue-tinted when picked.
struct OptionRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                SelectionMark(isSelected: isSelected)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, subtitle == nil ? 0 : 10)
            .frame(minHeight: 52)
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(isSelected ? CourtlyColor.blueTint : CourtlyColor.card)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Level

struct LevelSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var level: PlayerLevel?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "Level", canSave: level != nil, isSaving: isSaving, onSave: save) {
            VStack(spacing: 8) {
                ForEach(PlayerLevel.allCases) { option in
                    OptionRow(title: option.title, subtitle: option.description, isSelected: level == option) { level = option }
                }
            }
        }
        .onAppear { if level == nil { level = session.profile?.level } }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func save() {
        guard let level else { return }
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile(["level": level.rawValue])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - What you play

struct FormatsSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var formats: Set<PlayFormat> = []
    @State private var seeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        SheetScaffold(title: "What you play", canSave: !formats.isEmpty, isSaving: isSaving, onSave: save) {
            VStack(spacing: 8) {
                ForEach(PlayFormat.allCases) { option in
                    OptionRow(title: option.title, subtitle: option.description, isSelected: formats.contains(option)) {
                        if formats.contains(option) { formats.remove(option) } else { formats.insert(option) }
                    }
                }
            }
        }
        .onAppear {
            if !seeded {
                seeded = true
                formats = Set(session.profile?.formats ?? [])
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func save() {
        isSaving = true
        let ordered = PlayFormat.allCases.filter { formats.contains($0) }.map(\.rawValue)
        Task { @MainActor in
            do {
                try await session.updateProfile(["formats": ordered])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Area

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

// MARK: - Availability

struct AvailabilitySheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var mask = AvailabilityMask()
    @State private var blocked = AvailabilityMask()
    @State private var busy = AvailabilityMask()
    @State private var provider: CalendarProvider = .none
    @State private var seeded = false
    @State private var isConnecting = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var calendarService = CalendarService()

    var body: some View {
        SheetScaffold(title: "Availability", isSaving: isSaving, detents: [.large], onSave: save) {
            Text("Tap once when you’re free, twice when you’re busy.")
                .font(CourtlyFont.secondary)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.horizontal, 4)
                .padding(.bottom, 16)
            AvailabilityGrid(selected: $mask, busy: busy, blocked: $blocked)
            legend
                .padding(.top, 14)
                .padding(.horizontal, 4)
            Text("Hits during busy times stay out of your feed.")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 6)
                .padding(.horizontal, 4)

            SectionHeader(title: "Calendar", top: 28)
            Card {
                HStack(spacing: 14) {
                    CalendarIcon(size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Apple Calendar")
                            .font(CourtlyFont.body)
                            .foregroundStyle(CourtlyColor.ink)
                        Text(provider == .none ? "Marks times you have events as busy" : "Busy times come from your events")
                            .font(CourtlyFont.caption)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                    Spacer(minLength: 8)
                    if isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Toggle("Apple Calendar", isOn: Binding(get: { provider != .none }, set: { $0 ? connect() : disconnect() }))
                            .labelsHidden()
                            .tint(CourtlyColor.green)
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: 60)
            }
        }
        .onAppear {
            guard !seeded, let profile = session.profile else { return }
            seeded = true
            mask = profile.availability
            blocked = profile.busy
            busy = profile.busyThisWeek
            provider = profile.calendarProvider
        }
        .errorAlert($errorMessage)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(CourtlyColor.blue)
                    .frame(width: 12, height: 12)
                Text("Free")
            }
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(CourtlyColor.groupedBackground)
                    DiagonalStripes(spacing: 4)
                        .stroke(CourtlyColor.alertSeparator, lineWidth: 1)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .frame(width: 12, height: 12)
                Text("Busy")
            }
        }
        .font(CourtlyFont.caption)
        .foregroundStyle(CourtlyColor.secondary)
    }

    private func connect() {
        isConnecting = true
        Task { @MainActor in
            do {
                let result = try await calendarService.connect()
                provider = result.connection.provider
                busy = result.busy
            } catch {
                errorMessage = "Calendar access is off for Courtly. You can turn it on in Settings."
            }
            isConnecting = false
        }
    }

    private func disconnect() {
        provider = .none
        busy = AvailabilityMask()
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile([
                    "availability_mask": Int(mask.rawValue),
                    "busy_mask": Int(blocked.rawValue),
                    "busy_mask_week": Int(busy.rawValue),
                    "calendar_provider": provider.rawValue,
                ])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Edit profile

struct EditProfileSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var newPhoto: UIImage?
    @State private var photoToCrop: CropTarget?
    @State private var photoLoad = 0
    @State private var isLoadingPhoto = false
    @State private var seeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving && !isLoadingPhoto
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Edit profile")
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                HStack {
                    Button("Cancel") { dismiss() }
                        .font(CourtlyFont.body)
                        .foregroundStyle(CourtlyColor.blue)
                        .disabled(isSaving)
                    Spacer()
                    Button(isSaving ? "Saving…" : "Save", action: save)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.blue)
                        .disabled(!canSave)
                }
            }
            .frame(height: 52)

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 12) {
                        ZStack(alignment: .bottomTrailing) {
                            if let newPhoto {
                                Image(uiImage: newPhoto)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 120, height: 120)
                                    .clipShape(Circle())
                            } else if let card = session.profile?.card {
                                PlayerAvatar(card: card, size: 120)
                            }
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(Circle().fill(CourtlyColor.blue))
                                    .overlay(Circle().stroke(CourtlyColor.groupedBackground, lineWidth: 4))
                            }
                            .accessibilityLabel("Change photo")
                        }
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text("Change photo")
                                .font(CourtlyFont.secondarySemibold)
                                .foregroundStyle(CourtlyColor.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    Card {
                        VStack(spacing: 0) {
                            nameRow("First name", text: $firstName, contentType: .givenName)
                            HairlineSeparator()
                            nameRow("Last name", text: $lastName, contentType: .familyName)
                        }
                    }
                    .padding(.top, 24)
                    Text("Others see your first name and last initial.")
                        .font(CourtlyFont.caption)
                        .foregroundStyle(CourtlyColor.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 10)
                        .padding(.horizontal, 4)
                }
                .padding(.bottom, 24)
            }
        }
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .background(CourtlyColor.groupedBackground.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(20)
        .interactiveDismissDisabled(isSaving)
        .onAppear {
            guard !seeded, let profile = session.profile else { return }
            seeded = true
            firstName = profile.firstName
            lastName = profile.lastName
        }
        .onChange(of: pickerItem) { _, item in loadPhoto(item) }
        .fullScreenCover(item: $photoToCrop) { target in
            PhotoCropView(image: target.image) {
                photoToCrop = nil
                pickerItem = nil
            } onChoose: { cropped in
                newPhoto = cropped
                photoToCrop = nil
                pickerItem = nil   // the same photo can be picked and framed again
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func nameRow(_ label: String, text: Binding<String>, contentType: UITextContentType) -> some View {
        HStack {
            Text(label)
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.secondary)
            Spacer()
            TextField(label, text: text)
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(CourtlyColor.ink)
                .multilineTextAlignment(.trailing)
                .textContentType(contentType)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        photoLoad += 1
        let load = photoLoad
        isLoadingPhoto = true   // Save waits: the photo chosen is the photo saved
        Task { @MainActor in
            defer { if load == photoLoad { isLoadingPhoto = false } }
            guard let data = try? await item.loadTransferable(type: Data.self) else { return }
            // Decoding and scaling a camera photo is slow; keep it off the main thread. Kept large
            // enough that zooming in on a face in the cropper stays sharp.
            let image = await Task.detached(priority: .userInitiated) { UIImage(data: data)?.downscaled(to: 1800) }.value
            guard load == photoLoad, let image else { return }   // a newer pick has taken over
            photoToCrop = CropTarget(image: image)
        }
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            do {
                var patch: [String: Any] = [
                    "first_name": firstName.trimmingCharacters(in: .whitespaces),
                    "last_name": lastName.trimmingCharacters(in: .whitespaces),
                ]
                let previousPhoto = session.profile?.photoPath
                if let newPhoto, let data = newPhoto.jpegData(compressionQuality: 0.85), let me = session.profile?.id {
                    patch["photo_path"] = try await API.Profile.uploadPhoto(data, for: me)
                }
                try await session.updateProfile(patch)
                // The photo the profile stopped pointing at goes too; a failure here only leaves a stray file.
                if let previousPhoto, let current = patch["photo_path"] as? String, previousPhoto != current {
                    try? await API.Profile.removePhoto(at: previousPhoto)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// A picked photo waiting to be framed.
struct CropTarget: Identifiable {
    let id = UUID()
    let image: UIImage
}

extension UIImage {
    /// Shrinks the longest side to `maxSide` points at 1× so uploads stay small.
    func downscaled(to maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
