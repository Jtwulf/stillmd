import AppKit
import Foundation
import SwiftUI

@MainActor
final class ThemeState: ObservableObject {
    static let shared = ThemeState()

    private enum ObservationCenter: Sendable {
        case notification
        case distributed
    }

    private struct ObservationToken: @unchecked Sendable {
        let center: ObservationCenter
        let value: NSObjectProtocol
    }

    @Published private(set) var themePreference: ThemePreference = .system
    @Published private(set) var resolvedColorScheme: ColorScheme = .light

    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let distributedNotificationCenter: DistributedNotificationCenter
    private var observationTokens: [ObservationToken] = []

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        distributedNotificationCenter: DistributedNotificationCenter = .default()
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        self.distributedNotificationCenter = distributedNotificationCenter
        installObservers()
        scheduleThemeRefresh()
    }

    func scheduleThemeRefresh() {
        applyCurrentTheme()
    }

    @MainActor
    private func applyCurrentTheme() {
        let rawValue = userDefaults.string(forKey: AppPreferences.themeKey)
        let nextPreference = ThemePreference(rawValue: rawValue ?? "") ?? .system
        let appearance = NSApp.effectiveAppearance
        let nextResolvedScheme = nextPreference.resolvedColorScheme(using: appearance)

        if themePreference != nextPreference {
            themePreference = nextPreference
        }

        if resolvedColorScheme != nextResolvedScheme {
            resolvedColorScheme = nextResolvedScheme
        }
    }

    private func installObservers() {
        let defaultsToken = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleThemeRefresh()
            }
        }
        observationTokens.append(ObservationToken(center: .notification, value: defaultsToken))

        let appearanceToken = distributedNotificationCenter.addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleThemeRefresh()
            }
        }
        observationTokens.append(ObservationToken(center: .distributed, value: appearanceToken))
    }

    deinit {
        for token in observationTokens {
            switch token.center {
            case .notification:
                notificationCenter.removeObserver(token.value)
            case .distributed:
                distributedNotificationCenter.removeObserver(token.value)
            }
        }
    }
}
