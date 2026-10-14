import SwiftUI

/// Visual tokens from the design handoff. Every color and type size in the app comes from here.
enum CourtlyColor {
    static let ink = Color(hex: 0x0E1726)
    static let secondary = Color(hex: 0x5B6577)
    static let groupedBackground = Color(hex: 0xF4F5F7)
    static let separator = Color(hex: 0xE6E8EC)
    static let card = Color.white
    static let blue = Color(hex: 0x1F5BD8)
    static let blueDeep = Color(hex: 0x173F9E)
    static let blueTint = Color(hex: 0xEAF0FC)
    static let green = Color(hex: 0x2F7D57)
    static let red = Color(hex: 0xC2532F)
    static let lime = Color(hex: 0xE4F24A)
    static let alertSeparator = Color(hex: 0xD8DBE0)
}

enum CourtlyFont {
    static let largeTitle = Font.system(size: 34, weight: .bold)
    static let screenTitle = Font.system(size: 30, weight: .bold)
    static let sheetTitle = Font.system(size: 22, weight: .bold)
    static let sectionHeader = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 17)
    static let bodySemibold = Font.system(size: 17, weight: .semibold)
    static let secondary = Font.system(size: 15)
    static let secondarySemibold = Font.system(size: 15, weight: .semibold)
    static let caption = Font.system(size: 13)
    static let captionSemibold = Font.system(size: 13, weight: .semibold)

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
