import SwiftUI

/// Pick the part of a photo that goes in the circle, the way LinkedIn and Instagram do: drag to move,
/// pinch or slide to zoom. The image always covers the circle. Choose returns a square crop.
struct PhotoCropView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onChoose: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    static let maxZoom: CGFloat = 4
    static let outputSide: CGFloat = 600

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var pinchStart: CGFloat?
    @State private var isAdjusting = false

    var body: some View {
        GeometryReader { proxy in
            // Opened straight after the photo library closes, the cover can be laid out with no safe
            // area at all, which put Cancel and Choose under the status bar where taps never land.
            // The window's insets are the floor.
            let window = Self.windowInsets
            let top = max(0, window.top - proxy.safeAreaInsets.top)
            let bottom = max(0, window.bottom - proxy.safeAreaInsets.bottom)
            let diameter = min(proxy.size.width - 32, proxy.size.height - top - bottom - 220)
            let shown = displayedSize(diameter: diameter)
            VStack(spacing: 0) {
                HStack {
                    // Each button closes the screen itself as well as telling the owner, so the cover
                    // can never be left up if the owner's presentation state goes out of step.
                    Button {
                        dismiss()
                        onCancel()
                    } label: {
                        Text("Cancel")
                            .frame(minWidth: 64, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.white)
                    Spacer()
                    Text("Move and scale")
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        let cropped = crop(diameter: diameter)
                        dismiss()
                        onChoose(cropped)
                    } label: {
                        Text("Choose")
                            .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                    }
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.lime)
                }
                .font(CourtlyFont.body)
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .frame(height: 52)
                .background(Color.black)
                .zIndex(1)   // above the photo, which can spill past its frame when zoomed

                // The photo sits in an overlay so a wide or zoomed photo never widens the screen.
                Color.clear
                    .overlay {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: shown.width, height: shown.height)
                            .offset(offset)
                            .allowsHitTesting(false)   // a zoomed photo must never cover Cancel or Choose
                    }
                    .overlay {
                        CropMask(diameter: diameter)
                            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
                    }
                    .overlay {
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                            .frame(width: diameter, height: diameter)
                    }
                    .overlay {
                        if isAdjusting {
                            ThirdsGrid()
                                .stroke(Color.white.opacity(0.45), lineWidth: 0.5)
                                .frame(width: diameter, height: diameter)
                                .clipShape(Circle())
                        }
                    }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            isAdjusting = true
                            let start = dragStart ?? offset
                            dragStart = start
                            offset = clamped(CGSize(width: start.width + value.translation.width,
                                                    height: start.height + value.translation.height), diameter: diameter)
                        }
                        .onEnded { _ in dragStart = nil; isAdjusting = false }
                        .simultaneously(with:
                            MagnifyGesture()
                                .onChanged { value in
                                    isAdjusting = true
                                    let start = pinchStart ?? zoom
                                    pinchStart = start
                                    setZoom(start * value.magnification, diameter: diameter)
                                }
                                .onEnded { _ in pinchStart = nil; isAdjusting = false }
                        )
                )
                .accessibilityLabel("Photo. Drag to move, pinch to zoom.")

                HStack(spacing: 14) {
                    Image(systemName: "minus.magnifyingglass")
                    Slider(value: Binding(get: { zoom }, set: { setZoom($0, diameter: diameter) }), in: 1...Self.maxZoom)
                        .tint(CourtlyColor.lime)
                        .accessibilityLabel("Zoom")
                    Image(systemName: "plus.magnifyingglass")
                }
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .background(Color.black)
                .zIndex(1)
            }
            .padding(.top, top)
            .padding(.bottom, bottom)
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private static var windowInsets: UIEdgeInsets {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        return (windows.first(where: \.isKeyWindow) ?? windows.first)?.safeAreaInsets ?? .zero
    }

    /// At zoom 1 the photo's short side just fills the circle.
    private func displayedSize(diameter: CGFloat) -> CGSize {
        let fill = diameter / max(1, min(image.size.width, image.size.height))
        return CGSize(width: image.size.width * fill * zoom, height: image.size.height * fill * zoom)
    }

    private func setZoom(_ value: CGFloat, diameter: CGFloat) {
        zoom = min(max(value, 1), Self.maxZoom)
        offset = clamped(offset, diameter: diameter)   // zooming out never uncovers the circle
    }

    /// Keeps the photo's edges outside the circle.
    private func clamped(_ proposed: CGSize, diameter: CGFloat) -> CGSize {
        let shown = displayedSize(diameter: diameter)
        let maxX = max(0, (shown.width - diameter) / 2)
        let maxY = max(0, (shown.height - diameter) / 2)
        return CGSize(width: min(max(proposed.width, -maxX), maxX), height: min(max(proposed.height, -maxY), maxY))
    }

    /// The square of the photo under the circle, drawn at 600×600.
    private func crop(diameter: CGFloat) -> UIImage {
        let pointsPerImagePoint = displayedSize(diameter: diameter).width / image.size.width
        let side = diameter / pointsPerImagePoint
        let origin = CGPoint(
            x: image.size.width / 2 - offset.width / pointsPerImagePoint - side / 2,
            y: image.size.height / 2 - offset.height / pointsPerImagePoint - side / 2
        )
        let out = Self.outputSide
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: out, height: out), format: format).image { _ in
            let scale = out / side
            image.draw(in: CGRect(x: -origin.x * scale, y: -origin.y * scale,
                                  width: image.size.width * scale, height: image.size.height * scale))
        }
    }
}

/// The whole frame with a round hole in the middle, for dimming everything outside the circle.
private struct CropMask: Shape {
    let diameter: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addEllipse(in: CGRect(x: rect.midX - diameter / 2, y: rect.midY - diameter / 2, width: diameter, height: diameter))
        return path
    }
}

/// Rule-of-thirds lines, shown while adjusting.
private struct ThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            let y = rect.minY + rect.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: rect.minY)); path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.move(to: CGPoint(x: rect.minX, y: y)); path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}
