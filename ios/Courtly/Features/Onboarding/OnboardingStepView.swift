import SwiftUI

enum OnboardingAppearance { case original, courtside, courtsideBlue }

/// Shared layout for every onboarding step: back chevron + progress bar, 30pt title,
/// 15pt secondary subtitle, scrolling content, and a footer pinned above the home indicator.
struct OnboardingStepView<Content: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss

    let progress: Double
    let title: String
    let subtitle: String?
    let scrolls: Bool
    let appearance: OnboardingAppearance
    private var isCourtside: Bool { appearance != .original }
    private var isBlue: Bool { appearance == .courtsideBlue }
    private var background: Color { isBlue ? CourtlyColor.blue : isCourtside ? CourtlyColor.blueTint : .white }
    private var horizontalPadding: CGFloat { isCourtside ? 24 : CourtlyMetrics.screenPadding }
    private let content: () -> Content
    private let footer: (() -> Footer)?

    init(
        progress: Double,
        title: String,
        subtitle: String? = nil,
        scrolls: Bool = true,
        appearance: OnboardingAppearance = .original,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.appearance = appearance
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            if isCourtside {
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: { dismiss() }) {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isBlue ? .white : CourtlyColor.blue)
                            .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back")
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(isBlue ? Color.white.opacity(0.25) : CourtlyColor.line)
                            Capsule().fill(isBlue ? .white : CourtlyColor.blue)
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, horizontalPadding)
            } else {
                ProgressHeader(progress: progress) { dismiss() }
            }
            if scrolls {
                ScrollView {
                    stepContent
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            } else {
                stepContent
                Spacer(minLength: 0)
            }
        }
        .background(background.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let footer {
                footer()
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, isCourtside ? 8 : 16)
                    .background {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [background.opacity(0), background],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 28)
                            background
                        }
                        .padding(.top, -28)
                        .ignoresSafeArea()
                    }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// Title, subtitle and the step's own content.
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(isCourtside ? .system(size: 32, weight: .bold) : CourtlyFont.screenTitle)
                .tracking(-0.6)
                .lineSpacing(3)
                .foregroundStyle(isBlue ? .white : CourtlyColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(CourtlyFont.secondary)
                    .lineSpacing(3)
                    .foregroundStyle(isBlue ? .white.opacity(0.85) : CourtlyColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, isCourtside ? 12 : 20)
        .padding(.bottom, 24)
    }
}

extension OnboardingStepView where Footer == EmptyView {
    init(
        progress: Double,
        title: String,
        subtitle: String? = nil,
        scrolls: Bool = true,
        appearance: OnboardingAppearance = .original,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.appearance = appearance
        self.content = content
        self.footer = nil
    }
}

/// 44pt row: back chevron, 4pt progress track, 16pt trailing spacer.
struct ProgressHeader: View {
    let progress: Double
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CourtlyColor.ink)
                    .frame(width: 16, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(CourtlyColor.separator)
                    Capsule()
                        .fill(CourtlyColor.blue)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
            .animation(.easeInOut(duration: 0.35), value: progress)

            Spacer()
                .frame(width: 16)
        }
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .frame(height: 44)
    }
}

/// Keep recovery messages readable against the blue onboarding surface.
struct OnboardingErrorCaption: View {
    let text: String
    var body: some View {
        ErrorCaption(text: text)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 12))
    }
}
