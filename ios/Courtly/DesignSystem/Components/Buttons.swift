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

/// 52pt tall, 14pt radius. Blue on white screens, white on the blue welcome screen.
struct PrimaryButton: View {
    enum Style {
        case blue, white

        var background: Color { self == .blue ? CourtlyColor.blue : .white }
        var foreground: Color { self == .blue ? .white : CourtlyColor.blue }
    }

    let title: String
    var style: Style = .blue
    var isEnabled = true
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(CourtlyFont.bodySemibold)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .tint(style.foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: CourtlyMetrics.primaryButtonHeight)
            .foregroundStyle(style.foreground)
            .background(
                RoundedRectangle(cornerRadius: CourtlyMetrics.controlRadius, style: .continuous)
                    .fill(style.background)
            )
            .opacity(isEnabled ? 1 : 0.4)
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
