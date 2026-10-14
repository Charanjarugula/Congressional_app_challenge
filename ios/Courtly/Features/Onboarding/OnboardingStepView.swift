import SwiftUI

/// Shared layout for every onboarding step: back chevron + progress bar, 30pt title,
/// 15pt secondary subtitle, scrolling content, and a footer pinned above the home indicator.
struct OnboardingStepView<Content: View, Footer: View>: View {
    @Environment(\.dismiss) private var dismiss

    let progress: Double
    let title: String
    let subtitle: String?
    let scrolls: Bool
    private let content: () -> Content
    private let footer: (() -> Footer)?

    init(
        progress: Double,
        title: String,
        subtitle: String? = nil,
        scrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
        self.content = content
        self.footer = footer
    }

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(progress: progress) { dismiss() }
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
        .background(Color.white.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let footer {
                footer()
                    .padding(.horizontal, CourtlyMetrics.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .background {
                        VStack(spacing: 0) {
                            LinearGradient(
                                colors: [Color.white.opacity(0), Color.white],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 28)
                            Color.white
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
                .font(CourtlyFont.screenTitle)
                .tracking(-0.6)
                .lineSpacing(3)
                .foregroundStyle(CourtlyColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(CourtlyFont.secondary)
                    .lineSpacing(3)
                    .foregroundStyle(CourtlyColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, CourtlyMetrics.screenPadding)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }
}

extension OnboardingStepView where Footer == EmptyView {
    init(
        progress: Double,
        title: String,
        subtitle: String? = nil,
        scrolls: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.progress = progress
        self.title = title
        self.subtitle = subtitle
        self.scrolls = scrolls
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
