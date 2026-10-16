import SwiftUI

/// Scales down slightly while pressed. Used by every tappable card and button.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// 52pt tall, 14pt radius. Explicit styles keep screen-specific accents local.
struct PrimaryButton: View {
    enum Style {
        case blue, white, lime

        var background: Color {
            switch self {
            case .blue: CourtlyColor.blue
            case .white: .white
            case .lime: CourtlyColor.lime
            }
        }
        var foreground: Color {
            switch self {
            case .blue: .white
            case .white: CourtlyColor.blue
            case .lime: CourtlyColor.ink
            }
        }
    }

    let title: String
    var style: Style = .blue
    var compact = false
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(compact ? CourtlyFont.secondarySemibold : CourtlyFont.bodySemibold)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(style.foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: compact ? 48 : CourtlyMetrics.primaryButtonHeight)
            .foregroundStyle(style.foreground)
            .background(
                RoundedRectangle(cornerRadius: compact ? 16 : CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(!isEnabled && compact && style == .lime ? Color(hex: 0xC4D89B) : style.background)
            )
            .opacity(isEnabled || (compact && style == .lime) ? 1 : 0.4)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!isEnabled || isLoading)
    }
}

/// 48pt tall text-only button used under a primary button ("Not now", "I already have an account").
struct TextActionButton: View {
    let title: String
    var color: Color = CourtlyColor.secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CourtlyFont.bodySemibold)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Pill-shaped action used in people rows ("Add" / "Added").
struct PillButton: View {
    enum Style {
        case filled, tint
    }

    let title: String
    var style: Style = .filled
    var showsCheck = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if showsCheck {
                    CheckmarkShape()
                        .stroke(style == .filled ? CourtlyColor.ink : CourtlyColor.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 9, height: 5)
                }
                Text(title)
                    .font(CourtlyFont.secondarySemibold)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(style == .filled ? CourtlyColor.ink : CourtlyColor.blue)
            .background(Capsule().fill(style == .filled ? CourtlyColor.lime : CourtlyColor.blueTint))
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Inline link-style text button ("Change", "Manage", "Invite more").
struct LinkButton: View {
    let title: String
    var font: Font = CourtlyFont.secondarySemibold
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(font)
                .foregroundStyle(CourtlyColor.blue)
        }
        .buttonStyle(.plain)
    }
}
