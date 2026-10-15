import SwiftUI

enum MainTab: Int, CaseIterable, Identifiable {
    case play, myHits, people, you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .play: "Play"
        case .myHits: "My Hits"
        case .people: "People"
        case .you: "You"
        }
    }

    var symbol: String {
        switch self {
        case .play: "figure.tennis"
        case .myHits: "calendar"
        case .people: "bubble.left.and.bubble.right"
        case .you: "person.crop.circle"
        }
    }
}

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
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: .medium))
                            .frame(height: 26)
                        Text(tab.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(selected == tab ? CourtlyColor.lime : Color.white.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
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
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(CourtlyColor.ink)
                .shadow(color: CourtlyColor.ink.opacity(0.25), radius: 12, y: 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
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
                Circle()
                    .fill(CourtlyColor.lime)
                    .shadow(color: CourtlyColor.ink.opacity(0.2), radius: 12, y: 8)
            )
    }

    var body: some View {
        Button(action: action) { Self.face }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel(label)
    }
}
