import PhotosUI
import SwiftUI
import UIKit

enum ProfileSheet: String, Identifiable {
    case name, availability, level, formats, area

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

// MARK: - Edit profile

/// First and last name. Others see the first name and last initial.
struct NameSheet: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var seeded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        SheetScaffold(title: "Name", canSave: canSave, isSaving: isSaving, onSave: save) {
            SectionLabel(title: "First name")
                .padding(.bottom, 8)
            FieldBox(fill: CourtlyColor.card) {
                TextField("First name", text: $firstName)
                    .font(CourtlyFont.body)
                    .textContentType(.givenName)
                    .autocorrectionDisabled()
            }
            SectionLabel(title: "Last name")
                .padding(.top, 16)
                .padding(.bottom, 8)
            FieldBox(fill: CourtlyColor.card) {
                TextField("Last name", text: $lastName)
                    .font(CourtlyFont.body)
                    .textContentType(.familyName)
                    .autocorrectionDisabled()
            }
            Text("Others see your first name and last initial.")
                .font(CourtlyFont.caption)
                .foregroundStyle(CourtlyColor.secondary)
                .padding(.top, 10)
                .padding(.horizontal, 4)
        }
        .onAppear {
            guard !seeded, let profile = session.profile else { return }
            seeded = true
            firstName = profile.firstName
            lastName = profile.lastName
        }
        .errorAlert($errorMessage, title: "Couldn’t save")
    }

    private func save() {
        isSaving = true
        Task { @MainActor in
            do {
                try await session.updateProfile([
                    "first_name": firstName.trimmingCharacters(in: .whitespaces),
                    "last_name": lastName.trimmingCharacters(in: .whitespaces),
                ])
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

/// The profile photo on You: tap it to pick a new one, frame it in the circle, and it saves right away.
struct ProfilePhotoButton: View {
    @Environment(AppSession.self) private var session
    let card: PlayerCard
    var size: CGFloat = 96

    @State private var showsPicker = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var photoToCrop: CropTarget?
    @State private var pending: UIImage?   // shown while it uploads
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Button { showsPicker = true } label: {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let pending {
                        Image(uiImage: pending).resizable().scaledToFill()
                    } else {
                        PlayerAvatar(card: card, size: size)
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    if isWorking {
                        Circle().fill(Color.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
                Image(systemName: "camera.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(CourtlyColor.blue))
                    .overlay(Circle().stroke(CourtlyColor.groupedBackground, lineWidth: 3))
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel("Change profile photo")
        .photosPicker(isPresented: $showsPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in load(item) }
        // The cropper hangs off its own view, not the picker's: two presentations on one view can
        // leave the second stuck on screen after the first one closes.
        .background {
            Color.clear.fullScreenCover(item: $photoToCrop) { target in
                PhotoCropView(image: target.image) {
                    photoToCrop = nil
                    pickerItem = nil
                } onChoose: { cropped in
                    photoToCrop = nil
                    pickerItem = nil   // the same photo can be picked and framed again
                    upload(cropped)
                }
            }
        }
        .errorAlert($errorMessage, title: "Couldn’t change your photo")
    }

    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false }
            // Decoding a camera photo is slow; off the main thread, kept large enough to zoom in sharply.
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = await Task.detached(priority: .userInitiated, operation: { UIImage(data: data)?.downscaled(to: 1800) }).value {
                // Let the photo library finish sliding away before the cropper comes up.
                for _ in 0..<40 where showsPicker { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .milliseconds(350))
                photoToCrop = CropTarget(image: image)
            } else {
                pickerItem = nil   // so picking the same photo again tries again
                errorMessage = "That photo couldn’t be opened. If it’s in iCloud, wait for it to download and try again."
            }
        }
    }

    private func upload(_ image: UIImage) {
        guard let me = session.profile?.id, let data = image.jpegData(compressionQuality: 0.85) else { return }
        pending = image
        isWorking = true
        Task { @MainActor in
            defer { isWorking = false; pending = nil }
            do {
                let previous = session.profile?.photoPath
                let path = try await API.Profile.uploadPhoto(data, for: me)
                try await session.updateProfile(["photo_path": path])
                // The photo the profile stopped pointing at goes too; a failure here only leaves a stray file.
                if let previous, previous != path { try? await API.Profile.removePhoto(at: previous) }
            } catch {
                errorMessage = error.localizedDescription
            }
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
