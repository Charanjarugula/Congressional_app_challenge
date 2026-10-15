import SwiftUI

/// The band at the top of each tab: the title in white on court blue, with a faint top-down court
/// drawn behind it on the right and a tennis ball at the service line. Pinned above the content.
struct TabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
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
                .overlay(alignment: .topTrailing) {
                    CourtPlan()
                        .stroke(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .frame(width: 240, height: 320)
                        .offset(x: 56, y: 44)
                }
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(CourtlyColor.lime)
                        .frame(width: 11, height: 11)
                        .shadow(color: CourtlyColor.blueDeep.opacity(0.6), radius: 0, y: 3)
                        .offset(x: -36, y: 98)
                }
                .clipped()
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// A court seen from above, in a 300×400 box: sidelines, the net, the service line and center line.
struct CourtPlan: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 300
        var path = Path()
        path.addRoundedRect(in: CGRect(x: 20 * s, y: 10 * s, width: 260 * s, height: 400 * s), cornerSize: CGSize(width: 2 * s, height: 2 * s))
        path.move(to: CGPoint(x: 50 * s, y: 10 * s)); path.addLine(to: CGPoint(x: 50 * s, y: 410 * s))
        path.move(to: CGPoint(x: 250 * s, y: 10 * s)); path.addLine(to: CGPoint(x: 250 * s, y: 410 * s))
        path.move(to: CGPoint(x: 20 * s, y: 120 * s)); path.addLine(to: CGPoint(x: 280 * s, y: 120 * s))
        path.move(to: CGPoint(x: 50 * s, y: 35 * s)); path.addLine(to: CGPoint(x: 250 * s, y: 35 * s))
        path.move(to: CGPoint(x: 150 * s, y: 35 * s)); path.addLine(to: CGPoint(x: 150 * s, y: 120 * s))
        return path
    }
}
