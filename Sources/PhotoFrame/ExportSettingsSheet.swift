import SwiftUI

struct ExportSettingsSheet: View {
    let scope: ContentView.ExportScope
    let itemCount: Int
    let language: AppLanguage
    @Binding var format: ExportFormat
    @Binding var jpegQuality: Double
    @Binding var sizePreset: ExportSizePreset
    @Binding var customLongEdge: Int
    @Binding var filenamePrefix: String
    @Binding var copyMetadata: Bool
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.exportSettingsTitle(language))
                    .font(.title3.weight(.semibold))
                Text(L10n.exportDestination(language))
                    .font(.callout)
                    .foregroundColor(.secondary)
                Text(scopeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.exportFormat(language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $format) {
                        ForEach(ExportFormat.allCases) { exportFormat in
                            Text(exportFormat.title(language)).tag(exportFormat)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.exportSize(language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Picker("", selection: $sizePreset) {
                        ForEach(ExportSizePreset.allCases) { preset in
                            Text(preset.title(language)).tag(preset)
                        }
                    }
                    .labelsHidden()
                }

                if sizePreset == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.customLongEdge(language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("", value: $customLongEdge, format: .number)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.filenamePrefix(language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("", text: $filenamePrefix)
                        .textFieldStyle(.roundedBorder)
                }

                Toggle(L10n.copyMetadata(language), isOn: $copyMetadata)

                if format == .jpeg {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L10n.jpegQuality(language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int((jpegQuality * 100).rounded()))")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $jpegQuality, in: 0.5...1.0, step: 0.01)
                    }
                }
            }

            HStack {
                Spacer()
                Button(L10n.cancel(language)) { dismiss() }
                Button(L10n.exportAction(language)) {
                    dismiss()
                    onConfirm()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var scopeDescription: String {
        switch scope {
        case .selected:
            return L10n.processSelected(itemCount, language)
        case .all:
            return L10n.processAll(language)
        }
    }
}
