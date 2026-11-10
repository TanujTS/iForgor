import AppKit
import SwiftUI

/// Colors from the iForgor design, each with a light and a dark value.
enum Theme {
    static let background = dynamic(light: 0xFCFCFB, dark: 0x1C1C1E)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x2A2A2C)
    static let field = dynamic(light: 0xF3F3F1, dark: 0x2C2C2E)
    static let hairline = dynamic(light: 0xECECEA, dark: 0x38383A)
    static let ink = dynamic(light: 0x1D1D1F, dark: 0xF2F2F4)
    static let secondaryInk = dynamic(light: 0x3A3A3C, dark: 0xD1D1D6)
    static let muted = dynamic(light: 0x6E6E73, dark: 0x98989F)
    static let ring = dynamic(light: 0xC4C4C7, dark: 0x5A5A5E)
    static let accent = dynamic(light: 0x4F46E5, dark: 0x8B87FF)
    static let accentSoft = dynamic(light: 0xEEF0FF, dark: 0x2E2C4F)
    static let overdue = dynamic(light: 0xC2410C, dark: 0xFB923C)
    static let danger = dynamic(light: 0xB42318, dark: 0xF87171)
    static let success = dynamic(light: 0x16A34A, dark: 0x4ADE80)
    static let warning = dynamic(light: 0xD97706, dark: 0xFBBF24)

    static let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
