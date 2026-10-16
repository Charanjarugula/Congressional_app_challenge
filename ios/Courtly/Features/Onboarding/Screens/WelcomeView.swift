import SwiftUI

/// 01 · Welcome. Blue field, court lines, headline, Get started / I already have an account.
struct WelcomeView: View {
    let onGetStarted: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            CourtlyColor.blue.ignoresSafeArea()

            // On short screens (iPhone SE) the art shrinks so it stays clear of the headline.
            GeometryReader { proxy in
                CourtLinesArt()
                    .frame(maxWidth: .infinity, maxHeight: max(0, proxy.size.height - 330), alignment: .top)
                    .padding(.top, 40)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Text("Courtly")
                    .font(CourtlyFont.secondarySemibold)
                    .tracking(0.2)
                Text("Hit more.\nPlan less.")
                    .font(.system(size: 38, weight: .bold))
                    .tracking(-0.8)
                    .lineSpacing(1)
                    .padding(.top, 10)
                PrimaryButton(title: "Get started", style: .lime, action: onGetStarted)
                    .padding(.top, 36)
                Button(action: onSignIn) {
                    Text("I already have an account")
                        .font(CourtlyFont.secondarySemibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, CourtlyMetrics.screenPadding)
            .padding(.bottom, 16)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The welcome artwork: a court seen from the baseline, drawn as line segments on a 402×420 canvas.
struct CourtLinesArt: View {
    private struct Line {
        let x1: CGFloat
        let y1: CGFloat
        let x2: CGFloat
        let y2: CGFloat
        let width: CGFloat
        var opacity: Double = 1
    }

    private static let lines: [Line] = [
        Line(x1: 121, y1: 60, x2: 281, y2: 60, width: 2),
        Line(x1: -39, y1: 400, x2: 441, y2: 400, width: 3),
        Line(x1: 121, y1: 60, x2: -39, y2: 400, width: 2),
        Line(x1: 281, y1: 60, x2: 441, y2: 400, width: 2),
        Line(x1: 141, y1: 60, x2: 21, y2: 400, width: 2),
        Line(x1: 261, y1: 60, x2: 381, y2: 400, width: 2),
        Line(x1: 116, y1: 130, x2: 286, y2: 130, width: 2),
        Line(x1: 56, y1: 300, x2: 346, y2: 300, width: 2),
        Line(x1: 201, y1: 130, x2: 201, y2: 300, width: 2),
        Line(x1: 201, y1: 60, x2: 201, y2: 66, width: 2),
        Line(x1: 201, y1: 392, x2: 201, y2: 400, width: 2),
    ]

    var body: some View {
        Canvas { context, size in
            let scale = size.width / 402
            for line in Self.lines {
                var path = Path()
                path.move(to: CGPoint(x: line.x1 * scale, y: line.y1 * scale))
                path.addLine(to: CGPoint(x: line.x2 * scale, y: line.y2 * scale))
                context.stroke(
                    path,
                    with: .color(.white.opacity(line.opacity)),
                    style: StrokeStyle(lineWidth: line.width * scale, lineCap: .round)
                )
            }
            // Exact clean-net artwork from the approved Figma frame, on the same 402×420 canvas.
            context.draw(
                Image("WelcomeNet"),
                in: CGRect(x: 37.5 * scale, y: 164 * scale, width: 327 * scale, height: 57 * scale)
            )
            let shadow = Path(ellipseIn: CGRect(x: 293 * scale, y: 335 * scale, width: 18 * scale, height: 6 * scale))
            context.fill(shadow, with: .color(CourtlyColor.blueDeep))
            let ball = Path(ellipseIn: CGRect(x: 293 * scale, y: 321 * scale, width: 14 * scale, height: 14 * scale))
            context.fill(ball, with: .color(CourtlyColor.lime))
        }
        .aspectRatio(402 / 420, contentMode: .fit)
    }
}
