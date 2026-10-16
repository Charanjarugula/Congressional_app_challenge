import SwiftUI

/// The app's visual tokens. Every color and type size in the app comes from here.
enum CourtlyColor {
    static let surface = Color(hex: 0xF6F8FB)
    static let line = Color(hex: 0xE6EAF0)
    static let ink = Color(hex: 0x0E1726)
    static let secondary = Color(hex: 0x5B6577)
    static let groupedBackground = Color(hex: 0xF4F5F7)
    static let separator = Color(hex: 0xE6E8EC)
    static let card = Color.white
    static let blue = Color(hex: 0x1F5BD8)
    static let blueDeep = Color(hex: 0x173F9E)
    static let blueTint = Color(hex: 0xEAF0FC)
    static let green = Color(hex: 0x2F7D57)
    static let greenTint = Color(hex: 0xE6F2EC)
    static let placeholder = Color(hex: 0xC5C9D1)
    static let red = Color(hex: 0xC2532F)
    static let lime = Color(hex: 0xE4F24A)
    static let alertSeparator = Color(hex: 0xD8DBE0)
}

enum CourtlyFont {
    static let largeTitle = Font.largeTitle.bold()
    static let screenTitle = Font.system(size: 30, weight: .bold)
    static let sheetTitle = Font.title2.bold()
    static let sectionHeader = Font.body.weight(.semibold)
    static let body = Font.body
    static let bodySemibold = Font.body.weight(.semibold)
    static let secondary = Font.subheadline
    static let secondarySemibold = Font.subheadline.weight(.semibold)
    static let caption = Font.footnote
    static let captionSemibold = Font.footnote.weight(.semibold)

    /// Times and levels use SF Pro Rounded.
    static func rounded(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

enum CourtlyMetrics {
    static let screenPadding: CGFloat = 20
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 14
    static let primaryButtonHeight: CGFloat = 52
    static let fieldHeight: CGFloat = 56
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
