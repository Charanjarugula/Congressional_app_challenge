import SwiftUI

/// The floating glass pill with the four tabs. Content scrolls underneath it.
struct GlassTabBar: View {
    @Binding var selected: MainTab
    var dots: Set<MainTab> = []

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTab.allCases) { tab in
                Button {
                    selected = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(asset(for: tab))
                            .renderingMode(.template)
                            .frame(height: 26)
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selected == tab ? CourtlyColor.blue : CourtlyColor.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 54)
                    .background(selected == tab ? CourtlyColor.blueTint : .clear, in: RoundedRectangle(cornerRadius: 22))
                    .overlay(alignment: .topTrailing) {
                        if dots.contains(tab) {
                            Circle()
                                .fill(CourtlyColor.red)
                                .frame(width: 8, height: 8)
                                .offset(x: -22, y: 10)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected == tab ? [.isSelected] : [])
            }
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(CourtlyColor.line, lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
    private func asset(for tab: MainTab) -> String {
        switch tab {
        case .play: "CourtsideExplore"
        case .myHits: "CourtsideCalendar"
        case .people: "CourtsideChat"
        case .you: "CourtsideProfile"
        }
    }

}

/// "Plan a hit", floating above the tab bar on Play.
/// The one big plus, bottom right on Play and People: lime, navy glyph.
struct PlusButton: View {
    let label: String
    let action: () -> Void

    static var face: some View {
        Image(systemName: "plus")
            .font(.system(size: 26, weight: .bold))
            .foregroundStyle(CourtlyColor.ink)
            .frame(width: 56, height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(CourtlyColor.lime)
            )
    }

    var body: some View {
        Button(action: action) { Self.face }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(label)
    }
}
