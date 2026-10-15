import SwiftUI
import UIKit

/// A navigation bar item drawn as a bare glyph: no floating pill behind it on iOS 26.
struct PlainToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    @ViewBuilder let content: () -> Content

    var body: some ToolbarContent {
        if #available(iOS 26, *) {
            ToolbarItem(placement: placement) { content() }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) { content() }
        }
    }
}

extension View {
    /// A back chevron with nothing drawn around it, in place of the system button.
    func plainBackButton() -> some View { modifier(PlainBackButton()) }
}

private struct PlainBackButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .background(PopGestureEnabler().frame(width: 0, height: 0))
            .navigationBarBackButtonHidden(true)
            .toolbar {
                PlainToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(CourtlyColor.ink)
                            .frame(width: 32, height: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Back")
                }
            }
    }
}

/// Hiding the system back button switches off the swipe-back gesture; this turns it back on with the
/// system's own rules (on iOS 26 the swipe may start anywhere on the screen, as in every other app).
private struct PopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
            DispatchQueue.main.async { [weak self] in self?.enable() }
        }

        private func enable() {
            var node: UIViewController? = self
            var navigation: UINavigationController?
            while let current = node, navigation == nil {
                navigation = current as? UINavigationController ?? current.navigationController
                node = current.parent
            }
            guard let navigation else { return }
            // Both the edge recognizer and the full-screen pan iOS 26 adds check for the hidden back
            // button through their delegate; without one they behave as they do with the system button.
            for gesture in navigation.view.gestureRecognizers ?? [] where gesture is UIPanGestureRecognizer {
                gesture.delegate = nil
                gesture.isEnabled = true
            }
            navigation.interactivePopGestureRecognizer?.delegate = nil
            navigation.interactivePopGestureRecognizer?.isEnabled = true
        }
    }
}
