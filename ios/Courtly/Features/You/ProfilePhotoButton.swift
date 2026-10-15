import PhotosUI
import SwiftUI
import UIKit

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
