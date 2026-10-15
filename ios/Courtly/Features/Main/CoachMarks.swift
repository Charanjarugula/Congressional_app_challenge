import SwiftUI

/// Three tips over the real app the first time in: Friends and Explore on Play, the plus on People,
/// the plus on Play.
struct CoachMarksOverlay: View {
    let step: Int
    /// Where the plus is, in the overlay's space, so the second and third tips sit right above it.
    var pillFrame: CGRect? = nil
    var containerHeight: CGFloat = 0
    let onNext: () -> Void

    var body: some View {
        ZStack {
            CourtlyColor.ink.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture(perform: onNext)
            VStack {
                switch step {
                case 1:
                    Spacer()
                    tooltip(
                        text: "Friends shows hits your friends posted. Explore shows open hits near you. Tap a hit to see who’s in, then ask to join.",
                        counter: "1 of 3", button: "Next", arrow: nil
                    )
                    Spacer()
                        .frame(height: 220)
                case 2:
                    Spacer()
                    tooltip(
                        text: "Your chats and friend requests live here. Tap + to add friends or start a group.",
                        counter: "2 of 3", button: "Next", arrow: .bottom
                    )
                    .padding(.bottom, plusClearance)
                default:
                    Spacer()
                    tooltip(
                        text: "Nobody posted a time that works? Tap + to post your own. Pick a day, a court and how you want to play.",
                        counter: "3 of 3", button: "Got it", arrow: .bottom
                    )
                    .padding(.bottom, plusClearance)
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var plusClearance: CGFloat {
        pillFrame.map { containerHeight - $0.minY + 12 } ?? 160
    }

    private enum Arrow {
        case top, bottom
    }

    private func tooltip(text: String, counter: String, button: String, arrow: Arrow?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text)
                .font(CourtlyFont.secondary)
                .lineSpacing(4)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(counter)
                    .font(CourtlyFont.caption)
                    .foregroundStyle(Color(hex: 0x9AA1AD))
                Spacer()
                Button(action: onNext) {
                    Text(button)
                        .font(CourtlyFont.secondarySemibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CourtlyColor.ink)
        )
        .overlay(alignment: arrow == .top ? .topTrailing : .bottomTrailing) {
            if let arrow {
                Rectangle()
                    .fill(CourtlyColor.ink)
                    .frame(width: 12, height: 12)
                    .rotationEffect(.degrees(45))
                    .offset(x: -22, y: arrow == .top ? -6 : 6)   // over the plus, 48pt in from the screen edge
            }
        }
    }
}


/// Frames the first-run tips point at, published by the views that own them.
struct CoachAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]

    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}
