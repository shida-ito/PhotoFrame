import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PresetMenu: View {
    @ObservedObject var settings: FrameSettings
    @Binding var presetsData: Data
    @Binding var showingAlert: Bool
    let language: AppLanguage
    let theme: UIThemeAppearance
    let onRenamePreset: (Preset) -> Void
    let onPreviewPreset: (Preset?) -> Void
    let onApplyPreset: (Preset) -> Void

    @State private var showingPopover = false
    @State private var showingPastePresetSheet = false
    @State private var pastedPresetText = ""
    @State private var hoveredPresetID: UUID? = nil

    private var presets: [Preset] {
        PresetCodec.decodeStoredPresets(from: presetsData)
    }

    var body: some View {
        Button(action: { showingPopover.toggle() }) {
            Image(systemName: "slider.horizontal.3")
                .foregroundColor(.white.opacity(0.8))
                .padding(8)
                .background(theme.elevatedFill, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            presetPopover
                .onDisappear { endPresetPreview() }
        }
        .sheet(isPresented: $showingPastePresetSheet) {
            PresetTextImportSheet(
                language: language,
                text: $pastedPresetText,
                onImport: importPastedPresetText
            )
        }
    }

    private var presetPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.presets(language))
                    .font(.headline)
                Text(L10n.presetHoverPreview(language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if presets.isEmpty {
                Text(L10n.noPresetsSaved(language))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(presets) { preset in
                            PresetRow(
                                preset: preset,
                                language: language,
                                theme: theme,
                                isHovered: hoveredPresetID == preset.id,
                                onHoverChange: { isHovering in
                                    updateHoverState(for: preset, isHovering: isHovering)
                                },
                                onApply: { applyPreset(preset) },
                                onExport: { exportPreset(preset) },
                                onOverwrite: { overwritePreset(preset) },
                                onRename: {
                                    endPresetPreview()
                                    showingPopover = false
                                    onRenamePreset(preset)
                                },
                                onDelete: { deletePreset(id: preset.id) }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .onHover { isHovering in
                        if !isHovering {
                            endPresetPreview()
                        }
                    }
                }
                .frame(width: 360, height: min(CGFloat(max(presets.count, 1)) * 44.0, 260))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    actionButton(title: L10n.importPresets(language), systemImage: "square.and.arrow.down") {
                        importPresets()
                    }
                    actionButton(title: L10n.pastePresetText(language), systemImage: "doc.on.clipboard") {
                        pastedPresetText = ""
                        showingPastePresetSheet = true
                    }
                }

                HStack(spacing: 8) {
                    actionButton(title: L10n.saveCurrentAsPreset(language), systemImage: "plus") {
                        endPresetPreview()
                        showingPopover = false
                        showingAlert = true
                    }
                    if !presets.isEmpty {
                        actionButton(title: L10n.exportAllPresets(language), systemImage: "square.and.arrow.up") {
                            exportAllPresets(presets)
                        }
                    }
                }

                if !presets.isEmpty {
                    Button(role: .destructive, action: {
                        endPresetPreview()
                        presetsData = Data()
                    }) {
                        Label(L10n.clearAllPresets(language), systemImage: "trash")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 388)
    }

    private func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }

        do {
            var importedPresets: [Preset] = []
            for url in panel.urls {
                let data = try Data(contentsOf: url)
                importedPresets.append(contentsOf: try PresetCodec.decodeTransferPayload(from: data))
            }

            mergeImportedPresets(importedPresets)
        } catch {
            presentTransferError(
                title: L10n.presetImportFailed(language),
                message: errorMessage(for: error)
            )
        }
    }

    private func importPastedPresetText() {
        let trimmedText = pastedPresetText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        do {
            guard let data = trimmedText.data(using: .utf8) else {
                throw PresetCodecError.invalidPresetFile
            }

            let importedPresets = try PresetCodec.decodeTransferPayload(from: data)
            mergeImportedPresets(importedPresets)
            pastedPresetText = ""
            showingPastePresetSheet = false
        } catch {
            presentTransferError(
                title: L10n.presetImportFailed(language),
                message: errorMessage(for: error)
            )
        }
    }

    private func exportPreset(_ preset: Preset) {
        let suggestedFileName = PresetCodec.sanitizedFileNameComponent(from: preset.name)
        exportPresets([preset], suggestedFileName: suggestedFileName)
    }

    private func exportAllPresets(_ presets: [Preset]) {
        exportPresets(presets, suggestedFileName: "PhotoFrame-Presets")
    }

    private func exportPresets(_ presets: [Preset], suggestedFileName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(suggestedFileName).json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let exportData = try PresetCodec.encodeTransferPayload(for: presets)
            try exportData.write(to: url, options: .atomic)
        } catch {
            presentTransferError(
                title: L10n.presetExportFailed(language),
                message: error.localizedDescription
            )
        }
    }

    private func overwritePreset(_ preset: Preset) {
        var existingPresets = presets
        guard let index = existingPresets.firstIndex(where: { $0.id == preset.id }) else { return }

        var updatedPreset = settings.createPreset(name: preset.name)
        updatedPreset.id = preset.id
        existingPresets[index] = updatedPreset

        storePresets(existingPresets)
    }

    private func deletePreset(id: UUID) {
        var existingPresets = presets
        existingPresets.removeAll { $0.id == id }
        storePresets(existingPresets)
    }

    private func mergeImportedPresets(_ importedPresets: [Preset]) {
        guard !importedPresets.isEmpty else {
            presentTransferError(
                title: L10n.presetImportFailed(language),
                message: L10n.invalidPresetFile(language)
            )
            return
        }

        let mergedPresets = PresetCodec.mergedPresets(existing: presets, imported: importedPresets)
        storePresets(mergedPresets)
    }

    private func storePresets(_ presets: [Preset]) {
        if let encoded = PresetCodec.encodeStoredPresets(presets) {
            presetsData = encoded
        }
    }

    private func applyPreset(_ preset: Preset) {
        endPresetPreview()
        showingPopover = false
        onApplyPreset(preset)
    }

    private func updateHoverState(for preset: Preset, isHovering: Bool) {
        if isHovering {
            hoveredPresetID = preset.id
            onPreviewPreset(preset)
        } else if hoveredPresetID == preset.id {
            endPresetPreview()
        }
    }

    private func endPresetPreview() {
        hoveredPresetID = nil
        onPreviewPreset(nil)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(theme.elevatedFill, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func presentTransferError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }

    private func errorMessage(for error: Error) -> String {
        if case PresetCodecError.invalidPresetFile = error {
            return L10n.invalidPresetFile(language)
        }
        return error.localizedDescription
    }
}

private struct PresetRow: View {
    let preset: Preset
    let language: AppLanguage
    let theme: UIThemeAppearance
    let isHovered: Bool
    let onHoverChange: (Bool) -> Void
    let onApply: () -> Void
    let onExport: () -> Void
    let onOverwrite: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onApply) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)

            Menu {
                Button(L10n.exportPreset(language), action: onExport)
                Button(L10n.overwritePreset(language), action: onOverwrite)
                Divider()
                Button(L10n.renamePresetMenu(language), action: onRename)
                Button(L10n.deletePreset(language), role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.secondary)
                    .padding(4)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovered ? theme.selectionFill : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isHovered ? theme.selectionStroke : Color.secondary.opacity(0.08), lineWidth: 1)
        )
        .onHover(perform: onHoverChange)
    }
}

private struct PresetTextImportSheet: View {
    let language: AppLanguage
    @Binding var text: String
    let onImport: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.pastePresetTitle(language))
                    .font(.title3.weight(.semibold))
                Text(L10n.pastePresetMessage(language))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                if text.isEmpty {
                    Text(L10n.presetJSONPlaceholder(language))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            }
            .frame(minWidth: 520, idealWidth: 560, minHeight: 260, idealHeight: 320)

            HStack {
                Spacer()
                Button(L10n.cancel(language)) { dismiss() }
                Button(L10n.importPresetTextAction(language)) { onImport() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }
}
