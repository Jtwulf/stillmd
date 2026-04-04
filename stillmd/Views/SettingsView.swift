import SwiftUI

struct SettingsView: View {
    @AppStorage(AppPreferences.themeKey) private var themePreferenceRawValue =
        ThemePreference.system.rawValue
    @AppStorage(AppPreferences.textScaleKey) private var textScale = AppPreferences.defaultTextScale

    private var themePreferenceBinding: Binding<ThemePreference> {
        Binding(
            get: { ThemePreference(rawValue: themePreferenceRawValue) ?? .system },
            set: { themePreferenceRawValue = $0.rawValue }
        )
    }

    private var textScaleBinding: Binding<Double> {
        Binding(
            get: { AppPreferences.clampedTextScale(textScale) },
            set: { textScale = AppPreferences.clampedTextScale($0) }
        )
    }

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: themePreferenceBinding) {
                    ForEach(ThemePreference.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.radioGroup)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Text Scale")
                        Spacer()
                        Text("\(Int(AppPreferences.clampedTextScale(textScale) * 100))%")
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: textScaleBinding,
                        in: AppPreferences.textScaleRange,
                        step: 0.05
                    )
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }
}
