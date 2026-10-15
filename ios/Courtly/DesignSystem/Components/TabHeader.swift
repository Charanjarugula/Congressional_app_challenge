import SwiftUI

/// What a tab's header band draws behind its title, each about the tab itself.
enum TabHeaderArt {
    case play, myHits, people, you
}

/// The band at the top of each tab: the title in white on court blue, with flat shapes in deep blue
/// and lime behind it. Pinned above the scrolling content.
struct TabHeader<Trailing: View>: View {
    let title: String
    var art: TabHeaderArt
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, art: TabHeaderArt, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.art = art
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(CourtlyFont.largeTitle)
                .tracking(-0.8)
                .foregroundStyle(.white)
            Spacer(minLength: 0)
            trailing()
        }
        .frame(height: 52)
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background {
            CourtlyColor.blue
                .overlay { GeometryReader { proxy in artwork(in: proxy.size) } }
                .clipped()
                .ignoresSafeArea(edges: .top)
        }
    }

    // The design is drawn on a 390×130 band; everything scales from its width.
    @ViewBuilder
    private func artwork(in size: CGSize) -> some View {
        let s = size.width / 390
        let h = size.height
        // The band's top sits under the status bar, so the art keeps to the part below it.
        let v = max(h - 50, 56) / 130
        switch art {
        case .play:
            ZStack(alignment: .topLeading) {
                FlightPath(lift: 0).stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round, dash: [1, 7 * s]))
                FlightPath(lift: 30).stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5 * s, lineCap: .round, dash: [1, 7 * s]))
                Circle()
                    .fill(CourtlyColor.lime)
                    .frame(width: 22 * s, height: 22 * s)
                    .overlay(BallSeam().stroke(CourtlyColor.blue, lineWidth: 1.3 * s))
                    .position(x: 350 * s, y: h - 75 * v)
            }
        case .myHits:
            // Two rows of a week grid along the bottom edge, two days lit.
            ZStack(alignment: .topLeading) {
                ForEach(0..<8, id: \.self) { index in
                    let column = index % 4, row = index / 4
                    let lit = index == 1 || index == 6
                    if index != 3 {
                        RoundedRectangle(cornerRadius: 6 * s, style: .continuous)
                            .fill(lit ? CourtlyColor.lime : CourtlyColor.blueDeep)
                            .frame(width: 28 * s, height: 28 * s)
                            .offset(x: (240 + CGFloat(column) * 36) * s, y: h - (52 - CGFloat(row) * 36) * s)
                    }
                }
            }
        case .people:
            // Three overlapping circles, like avatars in a group, low on the right.
            ZStack(alignment: .topLeading) {
                Circle().fill(CourtlyColor.blueDeep).frame(width: 72 * s, height: 72 * s).position(x: 288 * s, y: h - 28)
                Circle().fill(Color.white.opacity(0.18)).frame(width: 72 * s, height: 72 * s).position(x: 344 * s, y: h - 36)
                Circle().fill(CourtlyColor.lime).frame(width: 42 * s, height: 42 * s).position(x: 316 * s, y: h - 58)
                Circle().fill(CourtlyColor.blueDeep).frame(width: 34 * s, height: 34 * s).position(x: 384 * s, y: h - 4)
            }
        case .you:
            // One thick ring cropped by the edge, like a profile frame, with a lime dot on it.
            ZStack(alignment: .topLeading) {
                Circle().strokeBorder(CourtlyColor.blueDeep, lineWidth: 14 * s).frame(width: 108 * s, height: 108 * s).position(x: 338 * s, y: h - 22)
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 8 * s).frame(width: 64 * s, height: 64 * s).position(x: 338 * s, y: h - 22)
                Circle().fill(CourtlyColor.lime).frame(width: 16 * s, height: 16 * s).position(x: 292 * s, y: h - 54)
            }
        }
    }
}

/// The arc a lobbed ball follows across the band, from the bottom-middle up to the right.
private struct FlightPath: Shape {
    var lift: CGFloat
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 390
        let v = max(rect.height - 50, 56) / 130
        var path = Path()
        path.move(to: CGPoint(x: (150 + lift) * s, y: rect.height + 2))
        path.addCurve(
            to: CGPoint(x: (350 + lift * 0.7) * s, y: rect.height - (75 - lift * 0.9) * v),
            control1: CGPoint(x: (210 + lift) * s, y: rect.height - (160 - lift) * v),
            control2: CGPoint(x: (280 + lift) * s, y: rect.height - (150 - lift) * v))
        return path
    }
}

/// The two curved seams on a tennis ball.
private struct BallSeam: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width, h = rect.height
        path.move(to: CGPoint(x: w * 0.2, y: h * 0.14))
        path.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.14), control: CGPoint(x: w * 0.5, y: h * 0.62))
        path.move(to: CGPoint(x: w * 0.2, y: h * 0.86))
        path.addQuadCurve(to: CGPoint(x: w * 0.8, y: h * 0.86), control: CGPoint(x: w * 0.5, y: h * 0.38))
        return path
    }
}
