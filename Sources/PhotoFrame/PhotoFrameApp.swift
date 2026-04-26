import SwiftUI

extension Notification.Name {
    static let photoFrameExportAllGroupSettings = Notification.Name("photoFrameExportAllGroupSettings")
    static let photoFrameImportAllGroupSettings = Notification.Name("photoFrameImportAllGroupSettings")
}

@main
struct PhotoFrameApp: App {
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .saveItem) {
                Divider()
                Button(L10n.exportAllGroupSettings(language)) {
                    NotificationCenter.default.post(name: .photoFrameExportAllGroupSettings, object: nil)
                }
                Button(L10n.importAllGroupSettings(language)) {
                    NotificationCenter.default.post(name: .photoFrameImportAllGroupSettings, object: nil)
                }
            }
        }

        Settings {
            PreferencesView()
        }
    }
}

struct PreferencesView: View {
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @AppStorage("fontSelectionDisplayMode") private var fontSelectionDisplayModeRaw = FontSelectionDisplayMode.compact.rawValue
    @AppStorage("fullscreenSlideshowAutoAdvanceGroups") private var fullscreenSlideshowAutoAdvanceGroups = false
    @AppStorage("defaultAudioDirectoryPath") private var defaultAudioDirectoryPath = ""
    @AppStorage("defaultLUTDirectoryPath") private var defaultLUTDirectoryPath = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    private var uiTheme: Binding<UITheme> {
        Binding(
            get: { UITheme(rawValue: uiThemeRaw) ?? .midnight },
            set: { uiThemeRaw = $0.rawValue }
        )
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

                Picker(L10n.colorMode(language), selection: uiTheme) {
                    ForEach(UITheme.allCases) { mode in
                        Text(mode.title(language)).tag(mode)
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

            Section {
                Toggle(L10n.autoAdvanceGroups(language), isOn: $fullscreenSlideshowAutoAdvanceGroups)
            } header: {
                Text(L10n.fullscreenSlideshowSettings(language))
            }

            Section {
                DefaultDirectoryField(
                    title: L10n.audioFolder(language),
                    path: $defaultAudioDirectoryPath,
                    placeholder: L10n.noFolderSelected(language),
                    chooseLabel: L10n.chooseFolder(language),
                    clearLabel: L10n.clearFolder(language)
                )

                DefaultDirectoryField(
                    title: L10n.lutFolder(language),
                    path: $defaultLUTDirectoryPath,
                    placeholder: L10n.noFolderSelected(language),
                    chooseLabel: L10n.chooseFolder(language),
                    clearLabel: L10n.clearFolder(language)
                )

                Text(L10n.defaultPathHint(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.defaultPaths(language))
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

struct DefaultDirectoryField: View {
    let title: String
    @Binding var path: String
    let placeholder: String
    let chooseLabel: String
    let clearLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            Text(path.isEmpty ? placeholder : path)
                .font(.caption)
                .foregroundStyle(path.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .lineLimit(2)
            HStack {
                Button(chooseLabel, action: chooseDirectory)
                if !path.isEmpty {
                    Button(clearLabel) {
                        path = ""
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                panel.directoryURL = url
            }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
    }
}
