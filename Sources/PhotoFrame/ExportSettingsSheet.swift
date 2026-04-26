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
    @Binding var secondsPerPhoto: Double
    @Binding var videoDurationMode: SlideshowVideoDurationMode
    let audioDisplayName: String?
    @Binding var includeOriginalVideoAudio: Bool
    @Binding var originalVideoAudioVolume: Double
    @Binding var backgroundAudioVolume: Double
    @Binding var fadeInEnabled: Bool
    @Binding var fadeInDuration: Double
    @Binding var fadeOutEnabled: Bool
    @Binding var fadeOutDuration: Double
    let isSlideshowWorkflow: Bool
    let containsImageItems: Bool
    let containsVideoItems: Bool
    let onChooseAudio: () -> Void
    let onClearAudio: () -> Void
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
                if isSlideshowWorkflow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.exportFormat(language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(ExportFormat.slideshowVideo.title(language))
                            .font(.callout.weight(.medium))
                    }
                } else if containsImageItems {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.exportFormat(language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("", selection: $format) {
                            ForEach(ExportFormat.imageFormats) { exportFormat in
                                Text(exportFormat.title(language)).tag(exportFormat)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
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

                if containsVideoItems {
                    Text(L10n.videoExportNote(language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if format == .slideshowVideo {
                    if containsVideoItems {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.slideshowVideoDurationMode(language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: $videoDurationMode) {
                                ForEach(SlideshowVideoDurationMode.allCases) { mode in
                                    Text(mode.title(language)).tag(mode)
                                }
                            }
                            .labelsHidden()
                            Text(L10n.slideshowVideoDurationHint(language))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(containsVideoItems ? L10n.slideshowSecondsPerItem(language) : L10n.slideshowSecondsPerPhoto(language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField(
                            "",
                            value: $secondsPerPhoto,
                            format: .number.precision(.fractionLength(1...2))
                        )
                        .textFieldStyle(.roundedBorder)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.slideshowAudio(language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack {
                            Text(audioDisplayName ?? L10n.noAudioSelected(language))
                                .font(.callout)
                                .foregroundColor(audioDisplayName == nil ? .secondary : .primary)
                                .lineLimit(1)
                            Spacer()
                            Button(L10n.chooseAudio(language), action: onChooseAudio)
                            if audioDisplayName != nil {
                                Button(L10n.clearAudio(language), action: onClearAudio)
                            }
                        }
                    }

                    if audioDisplayName != nil {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L10n.backgroundAudioVolume(language))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(Int((backgroundAudioVolume * 100).rounded()))%")
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            Slider(value: $backgroundAudioVolume, in: 0...1, step: 0.05)
                        }
                    }

                    if containsVideoItems {
                        Toggle(L10n.useOriginalVideoAudio(language), isOn: $includeOriginalVideoAudio)

                        if includeOriginalVideoAudio {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(L10n.originalVideoAudioVolume(language))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(Int((originalVideoAudioVolume * 100).rounded()))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $originalVideoAudioVolume, in: 0...1, step: 0.05)
                            }
                        }
                    }

                    Toggle(L10n.fadeIn(language), isOn: $fadeInEnabled)

                    if fadeInEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.fadeDuration(language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField(
                                "",
                                value: $fadeInDuration,
                                format: .number.precision(.fractionLength(1...2))
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    Toggle(L10n.fadeOut(language), isOn: $fadeOutEnabled)

                    if fadeOutEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.fadeDuration(language))
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField(
                                "",
                                value: $fadeOutDuration,
                                format: .number.precision(.fractionLength(1...2))
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                    }

                    Text(L10n.slideshowExportNote(language))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if containsImageItems && format == .jpeg {
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
        .frame(width: 460)
    }

    private var scopeDescription: String {
        if format == .slideshowVideo {
            switch scope {
            case .selected:
                return L10n.exportCurrentGroup(itemCount, language)
            case .all:
                return L10n.exportAllGroups(language)
            }
        }

        switch scope {
        case .selected:
            return L10n.processSelected(itemCount, language)
        case .all:
            return L10n.processAll(language)
        }
    }
}
