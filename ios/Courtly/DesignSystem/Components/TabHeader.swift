import SwiftUI

/// The band at the top of each tab: the title in white on court blue, with the baseline court lines
/// behind it. Pinned above the scrolling content.
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
            ZStack(alignment: .trailing) {
                CourtlyColor.blue
                CourtLinesArt()
                    .frame(width: 260)
                    .opacity(0.28)
                    .offset(x: 70, y: 10)
            }
            .clipped()
            .ignoresSafeArea(edges: .top)
        }
    }
}
