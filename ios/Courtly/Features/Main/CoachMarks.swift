import SwiftUI

/// Three tips over the real app the first time in: the hit list, adding friends, planning a hit.
struct CoachMarksOverlay: View {
    let step: Int
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
                        text: "These are hits other people have posted. Find one that works for you and ask to join.",
                        counter: "1 of 3", button: "Next", arrow: nil
                    )
                    Spacer()
                        .frame(height: 220)
                case 2:
                    tooltip(
                        text: "Add your friends here. Each friend gets their own chat.",
                        counter: "2 of 3", button: "Next", arrow: .top
                    )
                    .padding(.top, 66)
                    Spacer()
                default:
                    Spacer()
                    tooltip(
                        text: "Nobody posted a time that works? Post your own. Pick a day, a court and what you want to play.",
                        counter: "3 of 3", button: "Got it", arrow: .bottom
                    )
                    .padding(.bottom, 82 + 80)   // the pill floats above the tab bar
                }
            }
            .padding(.horizontal, CourtlyMetrics.screenPadding)
        }
        .transition(.opacity)
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
                    .offset(x: arrow == .top ? -28 : -60, y: arrow == .top ? -6 : 6)
            }
        }
    }
}
