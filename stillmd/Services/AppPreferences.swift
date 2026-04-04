import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

enum AppPreferences {
    static let themeKey = "themePreference"
    static let textScaleKey = "textScale"
    static let defaultTextScale = 1.0
    static let textScaleRange = 0.85...1.30
    static let textScaleStep = 0.05

    static func clampedTextScale(_ value: Double) -> Double {
        min(max(value, textScaleRange.lowerBound), textScaleRange.upperBound)
    }

    static func increasedTextScale(_ value: Double) -> Double {
        clampedTextScale(value + textScaleStep)
    }

    static func decreasedTextScale(_ value: Double) -> Double {
        clampedTextScale(value - textScaleStep)
    }

    static func resetTextScale() -> Double {
        defaultTextScale
    }
}
