import SwiftUI

/// Selectable row with a title, optional subtitle and a trailing selection mark.
/// Single-line rows use 18pt padding; rows with a subtitle use 16pt vertical.
struct ChoiceRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CourtlyFont.bodySemibold)
                        .foregroundStyle(CourtlyColor.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(CourtlyFont.secondary)
                            .foregroundStyle(CourtlyColor.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                SelectionMark(isSelected: isSelected)
            }
            .padding(.vertical, subtitle == nil ? 18 : 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(isSelected ? CourtlyColor.blueTint : CourtlyColor.groupedBackground)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// 56pt grouped-background container for text fields.
struct FieldBox<Content: View>: View {
    var isHighlighted = false
    var fill: Color = CourtlyColor.groupedBackground   // white on the grey sheets
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 12) {
            content()
        }
        .padding(.horizontal, 18)
        .frame(height: CourtlyMetrics.fieldHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                .fill(isHighlighted ? CourtlyColor.blueTint : fill)
        )
    }
}

/// Circle with two-letter initials. Used for people who are not on Courtly yet and for placeholders.
struct InitialsAvatar: View {
    enum Style {
        case tint, muted, blue

        var background: Color {
            switch self {
            case .tint: CourtlyColor.blueTint
            case .muted: CourtlyColor.groupedBackground
            case .blue: CourtlyColor.blue
            }
        }

        var foreground: Color {
            switch self {
            case .tint: CourtlyColor.blue
            case .muted: CourtlyColor.secondary
            case .blue: .white
            }
        }
    }

    let initials: String
    var size: CGFloat = 44
    var style: Style = .tint
    var ringed = false

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.33, weight: .bold))
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(style.background))
            .overlay {
                if ringed {
                    Circle().stroke(.white, lineWidth: 3)
                }
            }
    }
}

/// 1pt separator in the grouped palette.
struct HairlineSeparator: View {
    var body: some View {
        Rectangle()
            .fill(CourtlyColor.separator)
            .frame(height: 1)
    }
}

/// Section label above a list ("From your contacts", "How far will you travel for a hit?").
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(CourtlyFont.captionSemibold)
            .foregroundStyle(CourtlyColor.secondary)
    }
}
