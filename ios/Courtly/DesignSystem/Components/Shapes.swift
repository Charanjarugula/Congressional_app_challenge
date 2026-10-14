import SwiftUI

/// A check mark drawn as two strokes, sized by its frame.
struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

/// Diagonal hatching used for "busy" availability blocks.
struct DiagonalStripes: Shape {
    var spacing: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width + rect.height {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            x += spacing
        }
        return path
    }
}

/// The 24pt radio/check circle at the trailing edge of choice rows.
struct SelectionMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            if isSelected {
                Circle().fill(CourtlyColor.blue)
                CheckmarkShape()
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 6)
            } else {
                Circle().strokeBorder(CourtlyColor.separator, lineWidth: 1.5)
            }
        }
        .frame(width: 24, height: 24)
    }
}

/// Small green badge with a white check (calendar synced, confirmed states).
struct SuccessBadge: View {
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(CourtlyColor.green)
            CheckmarkShape()
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: size * 0.44, height: size * 0.22)
        }
        .frame(width: size, height: size)
    }
}
