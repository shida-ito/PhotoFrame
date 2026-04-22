import SwiftUI

@main
struct PhotoFrameApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)

        Settings {
            PreferencesView()
        }
    }
}

struct PreferencesView: View {
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue
    @AppStorage("fontSelectionDisplayMode") private var fontSelectionDisplayModeRaw = FontSelectionDisplayMode.compact.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    private var appLanguage: Binding<AppLanguage> {
        Binding(
            get: { language },
            set: { appLanguageRaw = $0.rawValue }
        )
    }

    private var fontSelectionDisplayMode: Binding<FontSelectionDisplayMode> {
        Binding(
            get: { FontSelectionDisplayMode(rawValue: fontSelectionDisplayModeRaw) ?? .compact },
            set: { fontSelectionDisplayModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            Section {
                Picker(L10n.displayLanguage(language), selection: appLanguage) {
                    ForEach(AppLanguage.allCases) { appLanguage in
                        Text(appLanguage.title).tag(appLanguage)
                    }
                }

                Picker(L10n.fontPickerMode(language), selection: fontSelectionDisplayMode) {
                    ForEach(FontSelectionDisplayMode.allCases) { mode in
                        Text(mode.title(language)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(currentDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if fontSelectionDisplayMode.wrappedValue == .classic {
                    Text(L10n.fullListWarning(language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L10n.interface(language))
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 420)
    }

    private var currentDescription: String {
        fontSelectionDisplayMode.wrappedValue.description(language)
    }
}
