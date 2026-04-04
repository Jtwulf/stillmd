import SwiftUI

enum WindowSurfacePalette {
    static func background(for colorScheme: ColorScheme) -> Color {
        switch colorScheme {
        case .dark:
            return Color(red: 0x15 / 255, green: 0x16 / 255, blue: 0x18 / 255)
        default:
            return Color(red: 0xfc / 255, green: 0xfc / 255, blue: 0xfa / 255)
        }
    }

    static func nsBackground(for colorScheme: ColorScheme) -> NSColor {
        switch colorScheme {
        case .dark:
            return NSColor(
                calibratedRed: 0x15 / 255,
                green: 0x16 / 255,
                blue: 0x18 / 255,
                alpha: 1
            )
        default:
            return NSColor(
                calibratedRed: 0xfc / 255,
                green: 0xfc / 255,
                blue: 0xfa / 255,
                alpha: 1
            )
        }
    }
}
