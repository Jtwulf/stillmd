import AppKit
import SwiftUI

enum ThemePreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static let defaultPreference: ThemePreference = .dark
    static let legacySystemRawValue = "system"

    static func normalized(
        from rawValue: String,
        fallbackAppearance: NSAppearance? = nil
    ) -> ThemePreference {
        if let preference = ThemePreference(rawValue: rawValue) {
            return preference
        }

        if rawValue == legacySystemRawValue {
            if let match = fallbackAppearance?.bestMatch(from: [.darkAqua, .aqua]) {
                return match == .darkAqua ? .dark : .light
            }
            return defaultPreference
        }

        return defaultPreference
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

    @MainActor
    static func migrateLegacyThemePreferenceIfNeeded(
        userDefaults: UserDefaults = .standard,
        appearance: NSAppearance = NSApp.effectiveAppearance
    ) -> ThemePreference {
        let rawValue = userDefaults.string(forKey: themeKey) ?? ThemePreference.defaultPreference.rawValue
        let preference = ThemePreference.normalized(from: rawValue, fallbackAppearance: appearance)
        if rawValue != preference.rawValue {
            userDefaults.set(preference.rawValue, forKey: themeKey)
        }
        return preference
    }
}
