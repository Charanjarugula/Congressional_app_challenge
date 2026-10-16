import SwiftUI

/// "Needs your reply", "From friends": 17/600 with the design's 22pt above and 8pt below.
struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: () -> Void = {}
    var top: CGFloat = 22

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(CourtlyFont.sectionHeader)
                .foregroundStyle(CourtlyColor.ink)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.blue)
                    .buttonStyle(.plain)
            }
        }
        .padding(.top, top)
        .padding(.bottom, 8)
    }
}

/// White 16pt-radius card.
struct Card<Content: View>: View {
    var padding: CGFloat = 0
    var radius: CGFloat = CourtlyMetrics.cardRadius
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(CourtlyColor.card))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A white card whose rows are separated by hairlines.
struct CardRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let items: Data
    var radius: CGFloat = CourtlyMetrics.cardRadius
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        Card(radius: radius) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { HairlineSeparator() }
                    row(item)
                }
            }
        }
    }
}

/// The small red line under a form when something went wrong.
struct ErrorCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(CourtlyFont.caption)
            .foregroundStyle(CourtlyColor.red)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Centered title and detail inside a white card, for empty and error states.
struct QuietCard: View {
    let title: String
    let detail: String

    var body: some View {
        Card(padding: 20) {
            VStack(spacing: 4) {
                Text(title)
                    .font(CourtlyFont.bodySemibold)
                    .foregroundStyle(CourtlyColor.ink)
                Text(detail)
                    .font(CourtlyFont.secondary)
                    .foregroundStyle(CourtlyColor.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// 50pt row with a title, an optional grey value and a chevron ("Level — Intermediate ›").
struct SettingsRow: View {
    let title: String
    var value: String? = nil
    var valueColor: Color = CourtlyColor.secondary
    var titleColor: Color = CourtlyColor.ink
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(CourtlyFont.body)
                    .foregroundStyle(titleColor)
                Spacer(minLength: 12)
                if let value {
                    Text(value)
                        .font(CourtlyFont.secondary)
                        .foregroundStyle(valueColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                if showsChevron {
                    ChevronMark()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Read-only 50pt row: title on the left, value on the right.
struct ValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(CourtlyFont.body)
                .foregroundStyle(CourtlyColor.ink)
            Spacer(minLength: 12)
            Text(value)
                .font(CourtlyFont.secondary)   // same size as the values on tappable rows
                .foregroundStyle(CourtlyColor.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
            .frame(minHeight: 50)
    }
}

/// Small grey chevron at the trailing edge of a row.
struct ChevronMark: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(CourtlyColor.placeholder)
    }
}

/// Coloured capsule in a hit's corner: Confirmed, Open, 1 spot, Played.
struct StatusPill: View {
    let kind: HitStatusKind

    var body: some View {
        Text(kind.title)
            .font(CourtlyFont.captionSemibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch kind {
        case .confirmed: CourtlyColor.green
        case .open: CourtlyColor.blue
        case .muted: CourtlyColor.secondary
        }
    }

    private var background: Color {
        switch kind {
        case .confirmed: CourtlyColor.greenTint
        case .open: CourtlyColor.blueTint
        case .muted: CourtlyColor.groupedBackground
        }
    }
}

/// 44pt, 12pt radius. Blue for the main action, grouped grey for the other one.
struct ActionButton: View {
    enum Style {
        case blue, grouped, lime, quiet
        /// White, for a button that sits on the grouped background itself rather than in a card.
        case card

        var background: Color {
            switch self {
            case .blue: CourtlyColor.blue
            case .lime: CourtlyColor.lime
            case .quiet: CourtlyColor.blueTint
            case .grouped: CourtlyColor.card
            case .card: CourtlyColor.card
            }
        }
        var foreground: Color { self == .blue ? .white : self == .lime ? CourtlyColor.ink : CourtlyColor.blue }
    }

    let title: String
    var style: Style = .blue
    var height: CGFloat = 44
    var radius: CGFloat = 12
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(CourtlyFont.secondarySemibold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(style.foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(style.foreground)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(style.background))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled || isLoading)
    }
}

/// Full-width red text ("Cancel hit", "Leave hit"), 52pt tall.
struct DestructiveTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(CourtlyColor.red)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Selectable 44pt chip used for formats and who-can-join.
struct Chip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CourtlyFont.secondarySemibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(isSelected ? .white : CourtlyColor.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? CourtlyColor.blue : CourtlyColor.card)
                )

        }
        .buttonStyle(SelectionButtonStyle())
    }
}

/// Two or three segments in a grey track ("Upcoming" / "Past").
struct SegmentedControl: View {
    let options: [String]
    @Binding var selectedIndex: Int
    var courtside = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { selectedIndex = index }
                } label: {
                    Text(option)
                        .font(courtside ? .subheadline.weight(.semibold) : CourtlyFont.captionSemibold)
                        .foregroundStyle(selectedIndex == index ? .white : CourtlyColor.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: courtside ? 44 : 32)
                        .background {
                            if selectedIndex == index {
                                RoundedRectangle(cornerRadius: courtside ? 11 : 8, style: .continuous)
                                    .fill(courtside ? CourtlyColor.blue : CourtlyColor.ink)
                            }
                        }
                        // The whole segment takes the tap, not just the letters: an unselected
                        // segment has no fill, and a plain button only hits what it draws.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selectedIndex == index ? [.isSelected] : [])
            }
        }
        .padding(courtside ? 4 : 2)
        .background(RoundedRectangle(cornerRadius: courtside ? 22 : 10, style: .continuous).fill(CourtlyColor.card))
    }
}

extension View {
    /// Shows a one-button alert whenever `message` is set, then clears it.
    func errorAlert(_ message: Binding<String?>, title: String = "Something went wrong") -> some View {
        alert(title, isPresented: Binding(get: { message.wrappedValue != nil }, set: { if !$0 { message.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
