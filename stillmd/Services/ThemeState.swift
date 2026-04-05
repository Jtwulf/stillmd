import Foundation
import SwiftUI

@MainActor
final class ThemeState: ObservableObject {
    static let shared = ThemeState()

    @Published private(set) var themePreference: ThemePreference = .defaultPreference
    private let userDefaults: UserDefaults
    private let notificationCenter: NotificationCenter
    nonisolated(unsafe) private var defaultsObserver: NSObjectProtocol?

    init(
        userDefaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default
    ) {
        self.userDefaults = userDefaults
        self.notificationCenter = notificationCenter
        installObservers()
        scheduleThemeRefresh()
    }

    func scheduleThemeRefresh() {
        applyCurrentTheme()
    }

    @MainActor
    private func applyCurrentTheme() {
        let nextPreference = AppPreferences.migrateLegacyThemePreferenceIfNeeded(
            userDefaults: userDefaults
        )

        if themePreference != nextPreference {
            themePreference = nextPreference
        }
    }

    private func installObservers() {
        defaultsObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: userDefaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleThemeRefresh()
            }
        }
    }

    deinit {
        if let defaultsObserver {
            notificationCenter.removeObserver(defaultsObserver)
        }
    }
}
