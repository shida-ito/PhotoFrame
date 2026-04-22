import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content View

struct ContentView: View {
    private static var hasRestoredWorkspaceInProcess = false

    private struct ClearUndoSnapshot {
        let photoGroups: [PhotoGroup]
        let selectedGroupID: UUID?
        let selectedItems: Set<UUID>
        let lastSelectedID: UUID?
    }

    enum ExportScope: String, Identifiable {
        case selected
        case all

        var id: String { rawValue }
    }

    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @StateObject private var settings = FrameSettings()
    @State private var photoGroups: [PhotoGroup] = [.ungrouped()]
    @State private var isProcessing = false
    @State private var isDragTargeted = false
    @State private var selectedGroupID: UUID? = nil
    @State private var selectedItems: Set<UUID> = []
    @State private var lastSelectedID: UUID? = nil
    @State private var previewImage: NSImage?
    @State private var isGeneratingPreview = false
    @State private var previewScheduleTask: Task<Void, Never>? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var isApplyingGroupSettings = false
    @State private var isRestoringWorkspace = false
    @State private var lastClearedSnapshot: ClearUndoSnapshot? = nil
    
    @AppStorage("userPresets") private var presetsData: Data = Data()
    @AppStorage("workspaceData") private var workspaceData: Data = Data()
    @AppStorage("previewMaxDim") private var previewMaxDim: Double = 600
    @AppStorage("exportFormat") private var exportFormatRaw = ExportFormat.jpeg.rawValue
    @AppStorage("exportJPEGQuality") private var exportJPEGQuality = 0.95
    @AppStorage("exportSizePreset") private var exportSizePresetRaw = ExportSizePreset.original.rawValue
    @AppStorage("exportCustomLongEdge") private var exportCustomLongEdge = 3000
    @AppStorage("exportFilenamePrefix") private var exportFilenamePrefix = "framed_"
    @AppStorage("exportCopyMetadata") private var exportCopyMetadata = true
    @State private var showingPresetAlert = false
    @State private var newPresetName: String = ""
    @State private var showingRenamePresetAlert = false
    @State private var presetRenameTargetID: UUID? = nil
    @State private var renamePresetName: String = ""
    @State private var showingAddGroupAlert = false
    @State private var newGroupName: String = ""
    @State private var showingRenameGroupAlert = false
    @State private var groupRenameTargetID: UUID? = nil
    @State private var renameGroupName: String = ""
    @State private var activeExportScope: ExportScope? = nil
    @State private var presetPreviewOriginalState: FrameSettingsState? = nil
    @State private var presetPreviewID: UUID? = nil
    private let photoGroupDragPrefix = "photoframe-photo-ids:"
    private let groupRowDragPrefix = "photoframe-group-id:"

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    private var uiTheme: UITheme {
        UITheme(rawValue: uiThemeRaw) ?? .midnight
    }

    private var theme: UIThemeAppearance {
        uiTheme.appearance
    }

    private var allPhotoItems: [PhotoItem] {
        photoGroups.flatMap(\.photoItems)
    }

    private var defaultGroupIndex: Int? {
        photoGroups.firstIndex(where: \.isDefaultGroup)
    }

    private var resolvedSelectedGroupIndex: Int? {
        if let selectedGroupID,
           let index = photoGroups.firstIndex(where: { $0.id == selectedGroupID }) {
            return index
        }
        return defaultGroupIndex ?? photoGroups.indices.first
    }

    private var selectedGroup: PhotoGroup? {
        guard let index = resolvedSelectedGroupIndex else { return nil }
        return photoGroups[index]
    }

    private var currentPreviewItem: PhotoItem? {
        guard let selectedGroup else { return nil }

        if let lastSelectedID,
           selectedItems.contains(lastSelectedID),
           let item = selectedGroup.photoItems.first(where: { $0.id == lastSelectedID }) {
            return item
        }

        return selectedGroup.photoItems.first(where: { selectedItems.contains($0.id) })
    }

    private var exportFormat: ExportFormat {
        get { ExportFormat(rawValue: exportFormatRaw) ?? .jpeg }
        nonmutating set { exportFormatRaw = newValue.rawValue }
    }

    private var exportSizePreset: ExportSizePreset {
        get { ExportSizePreset(rawValue: exportSizePresetRaw) ?? .original }
        nonmutating set { exportSizePresetRaw = newValue.rawValue }
    }

    private var currentExportSettings: ExportSettings {
        ExportSettings(
            format: exportFormat,
            jpegQuality: exportJPEGQuality,
            sizePreset: exportSizePreset,
            customLongEdge: exportCustomLongEdge,
            filenamePrefix: exportFilenamePrefix,
            copyMetadata: exportCopyMetadata
        )
    }

    private var exportFormatBinding: Binding<ExportFormat> {
        Binding(
            get: { exportFormat },
            set: { exportFormat = $0 }
        )
    }

    private var exportSizePresetBinding: Binding<ExportSizePreset> {
        Binding(
            get: { exportSizePreset },
            set: { exportSizePreset = $0 }
        )
    }

    var body: some View {
        ZStack {
            backgroundGradient
            mainHStack
        }
        .tint(theme.accent)
        .onAppear {
            restoreWorkspaceIfNeeded()
            if selectedGroupID == nil {
                selectedGroupID = photoGroups.first?.id
            }
            loadSelectedGroupSettings()
        }
        .onChange(of: selectedGroupID) {
            loadSelectedGroupSettings()
        }
        .onChange(of: settings.state) {
            persistSettingsToSelectedGroup()
        }
        .onChange(of: settings.editorConfiguration.backgroundPreviewSignature) {
            schedulePreviewRegeneration()
        }
        .sheet(item: $activeExportScope) { scope in
            ExportSettingsSheet(
                scope: scope,
                itemCount: exportItemCount(for: scope),
                language: language,
                format: exportFormatBinding,
                jpegQuality: $exportJPEGQuality,
                sizePreset: exportSizePresetBinding,
                customLongEdge: $exportCustomLongEdge,
                filenamePrefix: $exportFilenamePrefix,
                copyMetadata: $exportCopyMetadata,
                onConfirm: { confirmExport(scope) }
            )
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [theme.backgroundTop, theme.backgroundBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var mainHStack: some View {
        HStack(spacing: 0) {
            fileListPanel
                .frame(
                    minWidth: 220,
                    idealWidth: allPhotoItems.isEmpty ? 360 : 260,
                    maxWidth: allPhotoItems.isEmpty ? 420 : 300
                )

            Divider().background(theme.divider)
            previewPanel.frame(minWidth: 280, idealWidth: 320)

            Divider().background(theme.divider)
            settingsPanel.frame(width: 300)
        }
    }

    // MARK: - Panels

    private var fileListPanel: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(theme.divider)
            groupToolbar
            Divider().background(theme.divider)
            photoList
        }
        .alert(L10n.newGroupTitle(language), isPresented: $showingAddGroupAlert) {
            TextField(L10n.groupName(language), text: $newGroupName)
            Button(L10n.addGroup(language)) { addGroup() }
            Button(L10n.cancel(language), role: .cancel) { newGroupName = "" }
        } message: { Text(L10n.newGroupMessage(language)) }
        .alert(L10n.renameGroupTitle(language), isPresented: $showingRenameGroupAlert) {
            TextField(L10n.groupName(language), text: $renameGroupName)
            Button(L10n.rename(language)) { renameGroup() }
            Button(L10n.cancel(language), role: .cancel) { resetRenameGroupState() }
        } message: { Text(L10n.renameGroupMessage(language)) }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "photo.artframe")
                .font(.title2)
                .foregroundStyle(.linearGradient(colors: [theme.accentStart, theme.accentEnd], startPoint: .leading, endPoint: .trailing))
            Text("PhotoFrame").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.white)
            Spacer()
            if lastClearedSnapshot != nil {
                Button(action: undoClearPhotos) {
                    Label(L10n.undoClear(language), systemImage: "arrow.uturn.backward").font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(theme.elevatedFill, in: Capsule())
            }
            if !allPhotoItems.isEmpty {
                Button(action: clearPhotos) { Label(L10n.clearPhotos(language), systemImage: "trash").font(.caption) }
                    .buttonStyle(.plain).foregroundColor(.white.opacity(0.6)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(theme.elevatedFill, in: Capsule())
            }
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var groupToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    toolbarButton(title: L10n.addPhotos(language), systemImage: "plus.circle.fill", action: browseFiles)
                    toolbarButton(title: L10n.addGroup(language), systemImage: "folder.badge.plus") {
                        showingAddGroupAlert = true
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    toolbarButton(title: L10n.addPhotos(language), systemImage: "plus.circle.fill", action: browseFiles)
                    toolbarButton(title: L10n.addGroup(language), systemImage: "folder.badge.plus") {
                        showingAddGroupAlert = true
                    }
                }
            }

            if let selectedGroup {
                HStack(spacing: 8) {
                    Image(systemName: selectedGroup.isDefaultGroup ? "tray.full.fill" : "folder.fill")
                        .foregroundColor(theme.accent)
                    Text(selectedGroup.displayName(language))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.panelFill)
    }

    private var emptyPhotoState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(isDragTargeted ? theme.accent : theme.dropTargetStroke, style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isDragTargeted ? theme.accentSoft : theme.dropTargetFill)
                    )
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.linearGradient(colors: [theme.accentStart.opacity(0.7), theme.accentEnd.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    Text(L10n.dropJPEGFilesHere(language)).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180, maxHeight: 220)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleExternalDrop(providers: providers)
            }
            .onTapGesture { browseFiles() }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var photoList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 8) {
                    if allPhotoItems.isEmpty {
                        emptyPhotoState
                    }
                    ForEach(photoGroups) { group in
                        photoGroupSection(group)
                    }
                }
                .padding(8)
            }
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleExternalDrop(providers: providers)
            }
            Divider().background(theme.divider)
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.photoCount(allPhotoItems.count, language))
                    .font(.caption)
                    .foregroundColor(theme.secondaryText)
                processButtons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var processButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                processSelectedButton
                processAllButton
            }
            VStack(alignment: .leading, spacing: 8) {
                processSelectedButton
                processAllButton
            }
        }
    }

    private var processSelectedButton: some View {
        Button(action: { requestExport(scope: .selected) }) {
            HStack(spacing: 6) {
                Image(systemName: "selection.pin.in.out").font(.system(size: 12))
                Text(L10n.processSelected(selectedItems.count, language)).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(theme.elevatedFill)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing || selectedItems.isEmpty)
        .opacity(isProcessing || selectedItems.isEmpty ? 0.5 : 1.0)
    }

    private var processAllButton: some View {
        Button(action: { requestExport(scope: .all) }) {
            HStack(spacing: 6) {
                if isProcessing { ProgressView().controlSize(.small).tint(.white) }
                else { Image(systemName: "wand.and.stars").font(.system(size: 12)) }
                Text(isProcessing ? L10n.processing(language) : L10n.processAll(language)).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(LinearGradient(colors: [theme.accentStart, theme.accentEnd], startPoint: .leading, endPoint: .trailing))
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing || allPhotoItems.isEmpty)
        .opacity(isProcessing || allPhotoItems.isEmpty ? 0.7 : 1.0)
    }

    private func toolbarButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            toolbarButtonLabel(title: title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
    }

    private func toolbarButtonLabel(title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(theme.elevatedFill)
            .foregroundColor(.white)
            .clipShape(Capsule())
    }

    private func photoGroupSection(_ group: PhotoGroup) -> some View {
        let isSelectedGroup = group.id == selectedGroupID
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(action: { toggleGroupExpansion(group.id) }) {
                    Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
                .buttonStyle(.plain)

                Button(action: { selectGroup(group.id) }) {
                    HStack(spacing: 8) {
                        Image(systemName: group.isDefaultGroup ? "tray.full.fill" : "folder.fill")
                            .foregroundColor(isSelectedGroup ? theme.accent : .white.opacity(0.6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.displayName(language))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                            Text(L10n.photoCount(group.photoItems.count, language))
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.35))
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Menu {
                    Button(L10n.renameGroupMenu(language)) { beginRenamingGroup(group) }
                    if photoGroups.count > 1 {
                        Button(L10n.deleteGroup(language), role: .destructive) { deleteGroup(group.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white.opacity(0.45))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelectedGroup ? theme.selectionFill : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isSelectedGroup ? theme.selectionStroke : Color.white.opacity(0.04), lineWidth: 1)
            )
            .onDrag { makeGroupDragProvider(for: group.id) }

            if group.isExpanded {
                VStack(spacing: 4) {
                    ForEach(group.photoItems) { item in
                        PhotoRowView(
                            item: item,
                            isSelected: selectedItems.contains(item.id),
                            language: language,
                            onSelect: { selectItem(item, modifiers: NSEvent.modifierFlags) },
                            onRemove: { removePhotoSelection(startingWith: item) },
                            dragProvider: { makeDragProvider(for: item) }
                        )
                    }
                }
                .padding(.leading, 18)
            }
        }
        .onDrop(of: [.text, .fileURL], isTargeted: nil) { providers in
            handleGroupDrop(providers: providers, targetGroupID: group.id)
        }
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "eye.fill").font(.caption).foregroundColor(theme.accent)
                Text(L10n.preview(language)).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.8))
                Spacer()
                if let item = currentPreviewItem { Text(item.filename).font(.caption).foregroundColor(.white.opacity(0.4)).lineLimit(1) }
                Button(action: { selectedItems.removeAll(); previewImage = nil }) { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.3)) }.buttonStyle(.plain)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider().background(theme.divider)
            ZStack {
                theme.previewSurface
                if let preview = previewImage {
                    LivePreviewCanvas(
                        image: preview,
                        textLayers: currentPreviewTextLayers
                    )
                    .padding(20)
                    .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8)
                } else if !isGeneratingPreview {
                    Text(L10n.selectPhotoToPreview(language)).font(.caption).foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.settings(language)).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                        if let selectedGroup {
                            Text(L10n.editingGroup(selectedGroup.displayName(language), language))
                                .font(.caption2)
                                .foregroundColor(theme.tertiaryText)
                        }
                    }
                    Spacer()
                    PresetMenu(
                        settings: settings,
                        presetsData: $presetsData,
                        showingAlert: $showingPresetAlert,
                        language: language,
                        theme: theme,
                        onRenamePreset: beginRenamingPreset,
                        onPreviewPreset: previewPreset,
                        onApplyPreset: applyPresetToSelectedGroup
                    )
                }

                AspectRatioSettings(configuration: settings.editorConfigurationBinding, language: language)
                AlignmentSettings(configuration: settings.editorConfigurationBinding, language: language)
                FrameColorSettings(configuration: settings.editorConfigurationBinding, language: language)
                TextLayersSettings(
                    configuration: settings.editorConfigurationBinding,
                    language: language,
                    currentExifInfo: currentPreviewItem?.cachedExifInfo
                )
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Image(systemName: "square.dashed").font(.caption).foregroundColor(theme.accent); Text(L10n.frameWidth(language)).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
                    HStack {
                        Slider(value: settings.editorConfigurationBinding.paddingRatio, in: 0.0...0.15, step: 0.01).tint(theme.accent)
                        NumericField(value: settings.editorConfigurationBinding.paddingRatio).frame(width: 50).font(.caption2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "eye").font(.caption).foregroundColor(theme.accent)
                        Text(L10n.previewQuality(language)).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase)
                        Spacer()
                        Picker("", selection: $previewMaxDim) {
                            Text(L10n.previewFast(language)).tag(400.0)
                            Text(L10n.previewStandard(language)).tag(600.0)
                            Text(L10n.previewHigh(language)).tag(1000.0)
                            Text(L10n.previewUltra(language)).tag(1600.0)
                        }.labelsHidden().frame(width: 140)
                        .onChange(of: previewMaxDim) { invalidatePreviewCache() }
                    }
                }
            }.padding(20)
        }.background(theme.panelFill)
        .alert(L10n.savePresetTitle(language), isPresented: $showingPresetAlert) {
            TextField(L10n.presetName(language), text: $newPresetName)
            Button(L10n.save(language)) { savePreset() }
            Button(L10n.cancel(language), role: .cancel) { }
        } message: { Text(L10n.savePresetMessage(language)) }
        .alert(L10n.renamePresetTitle(language), isPresented: $showingRenamePresetAlert) {
            TextField(L10n.presetName(language), text: $renamePresetName)
            Button(L10n.rename(language)) { renamePreset() }
            Button(L10n.cancel(language), role: .cancel) { resetRenamePresetState() }
        } message: { Text(L10n.renamePresetMessage(language)) }
    }
    
    private func savePreset() {
        let presetName = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !presetName.isEmpty else { return }
        var presets = decodedPresets()
        presets.append(settings.createPreset(name: presetName))
        storePresets(presets)
        newPresetName = ""
    }

    private func beginRenamingPreset(_ preset: Preset) {
        presetRenameTargetID = preset.id
        renamePresetName = preset.name
        showingRenamePresetAlert = true
    }

    private func renamePreset() {
        let presetName = renamePresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !presetName.isEmpty, let targetID = presetRenameTargetID else { return }

        var presets = decodedPresets()
        guard let index = presets.firstIndex(where: { $0.id == targetID }) else {
            resetRenamePresetState()
            return
        }

        presets[index].name = presetName
        storePresets(presets)
        resetRenamePresetState()
    }

    private func resetRenamePresetState() {
        presetRenameTargetID = nil
        renamePresetName = ""
        showingRenamePresetAlert = false
    }

    private func decodedPresets() -> [Preset] {
        PresetCodec.decodeStoredPresets(from: presetsData)
    }

    private func storePresets(_ presets: [Preset]) {
        if let encoded = PresetCodec.encodeStoredPresets(presets) {
            presetsData = encoded
        }
    }

    private func restoreWorkspaceIfNeeded() {
        guard !Self.hasRestoredWorkspaceInProcess else { return }
        Self.hasRestoredWorkspaceInProcess = true
        restoreWorkspace()
    }

    private func restoreWorkspace() {
        guard !workspaceData.isEmpty,
              let snapshot = try? JSONDecoder().decode(PersistedWorkspace.self, from: workspaceData) else {
            return
        }

        isRestoringWorkspace = true

        var restoredGroups = snapshot.groups.map { persistedGroup in
            let restoredItems = persistedGroup.photoPaths.compactMap { path -> PhotoItem? in
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: url.path) else { return nil }
                return PhotoItem(url: url)
            }

            return PhotoGroup(
                id: persistedGroup.id,
                name: persistedGroup.name,
                isDefaultGroup: persistedGroup.isDefaultGroup,
                isExpanded: persistedGroup.isExpanded,
                settingsState: persistedGroup.settingsState,
                photoItems: restoredItems
            )
        }

        if restoredGroups.isEmpty {
            restoredGroups = [.ungrouped()]
        } else if !restoredGroups.contains(where: \.isDefaultGroup) {
            restoredGroups.insert(.ungrouped(), at: 0)
        }

        photoGroups = restoredGroups
        if let restoredSelectedGroupID = snapshot.selectedGroupID,
           restoredGroups.contains(where: { $0.id == restoredSelectedGroupID }) {
            selectedGroupID = restoredSelectedGroupID
        } else {
            selectedGroupID = restoredGroups.first?.id
        }

        restoreInitialSelection()
        loadSelectedGroupSettings()

        for group in photoGroups {
            for item in group.photoItems {
                startLoadingAssets(for: item, url: item.url)
            }
        }

        isRestoringWorkspace = false
        saveWorkspace()
    }

    private func restoreInitialSelection() {
        guard let index = resolvedSelectedGroupIndex,
              let firstItem = photoGroups[index].photoItems.first else {
            selectedItems.removeAll()
            lastSelectedID = nil
            previewImage = nil
            return
        }

        selectedItems = [firstItem.id]
        lastSelectedID = firstItem.id
    }

    private func captureClearUndoSnapshot() -> ClearUndoSnapshot {
        ClearUndoSnapshot(
            photoGroups: photoGroups,
            selectedGroupID: selectedGroupID,
            selectedItems: selectedItems,
            lastSelectedID: lastSelectedID
        )
    }

    private func restore(from snapshot: ClearUndoSnapshot) {
        photoGroups = snapshot.photoGroups
        selectedGroupID = snapshot.selectedGroupID
        selectedItems = snapshot.selectedItems
        lastSelectedID = snapshot.lastSelectedID
        loadSelectedGroupSettings()
        schedulePreviewRegeneration(delayNanoseconds: 0)
        saveWorkspace()
    }

    private func saveWorkspace() {
        guard !isRestoringWorkspace else { return }

        let snapshot = PersistedWorkspace(
            selectedGroupID: selectedGroupID,
            groups: photoGroups.map { group in
                PersistedPhotoGroup(
                    id: group.id,
                    name: group.name,
                    isDefaultGroup: group.isDefaultGroup,
                    isExpanded: group.isExpanded,
                    settingsState: group.settingsState,
                    photoPaths: group.photoItems.map { $0.url.path }
                )
            }
        )

        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        workspaceData = encoded
    }

    private func startLoadingAssets(for item: PhotoItem, url: URL) {
        Task.detached {
            let thumb = ImageProcessor.generateThumbnail(for: url)
            let maxDim = await self.previewMaxDim
            let previewData = PhotoItem.loadPreviewData(from: url, maxDim: CGFloat(maxDim))
            await MainActor.run {
                item.thumbnail = thumb
                if let (cg, exif, orient, ow, oh) = previewData {
                    item.cachedPreviewImage = cg
                    item.cachedExifInfo = exif
                    item.cachedOrientation = orient
                    item.cachedOrientedSize = (ow, oh)
                }
            }
        }
    }

    private func loadSelectedGroupSettings() {
        guard let index = resolvedSelectedGroupIndex else { return }
        let targetState = photoGroups[index].settingsState
        guard settings.state != targetState else { return }

        isApplyingGroupSettings = true
        settings.apply(state: targetState)
        isApplyingGroupSettings = false
    }

    private func persistSettingsToSelectedGroup() {
        guard !isApplyingGroupSettings,
              let index = resolvedSelectedGroupIndex else { return }

        let currentState = settings.state
        guard photoGroups[index].settingsState != currentState else { return }
        photoGroups[index].settingsState = currentState
        saveWorkspace()
    }

    private func addGroup() {
        let groupName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty else { return }

        let group = PhotoGroup(
            name: groupName,
            settingsState: settings.state
        )
        photoGroups.append(group)
        selectedGroupID = group.id
        selectedItems.removeAll()
        lastSelectedID = nil
        previewImage = nil
        newGroupName = ""
        showingAddGroupAlert = false
        saveWorkspace()
    }

    private func beginRenamingGroup(_ group: PhotoGroup) {
        groupRenameTargetID = group.id
        renameGroupName = group.displayName(language)
        showingRenameGroupAlert = true
    }

    private func renameGroup() {
        let groupName = renameGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty,
              let targetID = groupRenameTargetID,
              let index = photoGroups.firstIndex(where: { $0.id == targetID }) else {
            resetRenameGroupState()
            return
        }

        photoGroups[index].name = groupName
        resetRenameGroupState()
        saveWorkspace()
    }

    private func resetRenameGroupState() {
        groupRenameTargetID = nil
        renameGroupName = ""
        showingRenameGroupAlert = false
    }

    private func toggleGroupExpansion(_ groupID: UUID) {
        guard let index = photoGroups.firstIndex(where: { $0.id == groupID }) else { return }
        photoGroups[index].isExpanded.toggle()
        saveWorkspace()
    }

    private func selectGroup(_ groupID: UUID) {
        guard let index = photoGroups.firstIndex(where: { $0.id == groupID }) else { return }

        selectedGroupID = groupID
        if let firstItem = photoGroups[index].photoItems.first {
            selectedItems = [firstItem.id]
            lastSelectedID = firstItem.id
        } else {
            selectedItems.removeAll()
            lastSelectedID = nil
            previewImage = nil
        }
        saveWorkspace()
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    private func deleteGroup(_ groupID: UUID) {
        guard photoGroups.count > 1,
              let index = photoGroups.firstIndex(where: { $0.id == groupID }) else { return }

        let removedGroup = photoGroups.remove(at: index)
        let fallbackIndex = photoGroups.firstIndex(where: \.isDefaultGroup) ?? min(index, photoGroups.count - 1)

        if removedGroup.isDefaultGroup {
            for groupIndex in photoGroups.indices {
                photoGroups[groupIndex].isDefaultGroup = groupIndex == fallbackIndex
            }
        }

        photoGroups[fallbackIndex].photoItems.append(contentsOf: removedGroup.photoItems)
        selectedGroupID = selectedGroupID == groupID ? photoGroups[fallbackIndex].id : selectedGroupID
        refreshSelectionAfterPhotoMutation(preferredGroupID: selectedGroupID ?? photoGroups[fallbackIndex].id)
    }

    private func movePhotos(withIDs itemIDs: Set<UUID>, to targetGroupID: UUID) {
        guard let targetIndex = photoGroups.firstIndex(where: { $0.id == targetGroupID }) else { return }

        var movedItems: [PhotoItem] = []
        for index in photoGroups.indices {
            guard index != targetIndex else { continue }
            let extractedItems = photoGroups[index].photoItems.filter { itemIDs.contains($0.id) }
            if !extractedItems.isEmpty {
                movedItems.append(contentsOf: extractedItems)
                photoGroups[index].photoItems.removeAll { itemIDs.contains($0.id) }
            }
        }

        guard !movedItems.isEmpty else { return }
        photoGroups[targetIndex].photoItems.append(contentsOf: movedItems)
        photoGroups[targetIndex].isExpanded = true
        selectedGroupID = targetGroupID
        selectedItems = itemIDs
        if let firstMoved = movedItems.first {
            lastSelectedID = firstMoved.id
        }
        saveWorkspace()
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    private func reorderGroup(_ sourceGroupID: UUID, before targetGroupID: UUID) {
        guard sourceGroupID != targetGroupID,
              let sourceIndex = photoGroups.firstIndex(where: { $0.id == sourceGroupID }),
              let targetIndex = photoGroups.firstIndex(where: { $0.id == targetGroupID }) else {
            return
        }

        let movedGroup = photoGroups.remove(at: sourceIndex)
        let insertionIndex = sourceIndex < targetIndex ? targetIndex - 1 : targetIndex
        photoGroups.insert(movedGroup, at: insertionIndex)
        saveWorkspace()
    }

    private func makeDragProvider(for item: PhotoItem) -> NSItemProvider {
        if !selectedItems.contains(item.id) {
            selectedItems = [item.id]
            lastSelectedID = item.id
            if let groupIndex = groupIndex(containing: item.id) {
                selectedGroupID = photoGroups[groupIndex].id
            }
        }

        let itemIDs = selectedItems.contains(item.id) ? selectedItems : [item.id]
        let payload = photoGroupDragPrefix + itemIDs.map(\.uuidString).joined(separator: ",")
        return NSItemProvider(object: payload as NSString)
    }

    private func makeGroupDragProvider(for groupID: UUID) -> NSItemProvider {
        let payload = groupRowDragPrefix + groupID.uuidString
        return NSItemProvider(object: payload as NSString)
    }

    private func handleGroupDrop(providers: [NSItemProvider], targetGroupID: UUID) -> Bool {
        let handledReorder = handleGroupReorderDrop(providers: providers, targetGroupID: targetGroupID)
        let handledMove = handlePhotoMoveDrop(providers: providers, targetGroupID: targetGroupID)
        let handledExternalDrop = handleExternalDrop(providers: providers, targetGroupID: targetGroupID)
        return handledReorder || handledMove || handledExternalDrop
    }

    private func handleGroupReorderDrop(providers: [NSItemProvider], targetGroupID: UUID) -> Bool {
        let supportedProviders = providers.filter { $0.canLoadObject(ofClass: NSString.self) }
        guard !supportedProviders.isEmpty else { return false }

        for provider in supportedProviders {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String,
                      string.hasPrefix(groupRowDragPrefix) else { return }

                let groupIDString = String(string.dropFirst(groupRowDragPrefix.count))
                guard let sourceGroupID = UUID(uuidString: groupIDString) else { return }

                Task { @MainActor in
                    reorderGroup(sourceGroupID, before: targetGroupID)
                }
            }
        }

        return true
    }

    private func handlePhotoMoveDrop(providers: [NSItemProvider], targetGroupID: UUID) -> Bool {
        let supportedProviders = providers.filter { $0.canLoadObject(ofClass: NSString.self) }
        guard !supportedProviders.isEmpty else { return false }

        for provider in supportedProviders {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String,
                      string.hasPrefix(photoGroupDragPrefix) else { return }

                let idStrings = string
                    .dropFirst(photoGroupDragPrefix.count)
                    .split(separator: ",")
                    .map(String.init)
                let ids = Set(idStrings.compactMap(UUID.init(uuidString:)))
                guard !ids.isEmpty else { return }

                Task { @MainActor in
                    movePhotos(withIDs: ids, to: targetGroupID)
                }
            }
        }

        return true
    }

    private func groupIndex(containing itemID: UUID) -> Int? {
        photoGroups.firstIndex { group in
            group.photoItems.contains { $0.id == itemID }
        }
    }

    // MARK: - Handlers

    private func handleExternalDrop(providers: [NSItemProvider], targetGroupID: UUID? = nil) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !fileProviders.isEmpty else { return false }

        for provider in fileProviders {
            Self.loadDroppedFileURLs(from: provider) { urls in
                let jpegURLs = urls
                    .map(\.standardizedFileURL)
                    .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                guard !jpegURLs.isEmpty else { return }

                Task { @MainActor in
                    for url in jpegURLs {
                        addPhoto(url: url, to: targetGroupID)
                    }
                }
            }
        }

        return true
    }

    private static func loadDroppedFileURLs(
        from provider: NSItemProvider,
        completion: @escaping @Sendable ([URL]) -> Void
    ) {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
            if let data,
               let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) {
                completion([url])
            }
        }
    }

    private func browseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [UTType.jpeg]
        if panel.runModal() == .OK { panel.urls.forEach { addPhoto(url: $0) } }
    }

    private func addPhoto(url: URL, to targetGroupID: UUID? = nil) {
        let normalizedURL = url.standardizedFileURL
        guard !allPhotoItems.contains(where: { $0.url.standardizedFileURL == normalizedURL }) else { return }
        let item = PhotoItem(url: normalizedURL)

        let targetIndex: Int
        if let targetGroupID,
           let resolvedIndex = photoGroups.firstIndex(where: { $0.id == targetGroupID }) {
            targetIndex = resolvedIndex
        } else {
            targetIndex = resolvedSelectedGroupIndex ?? 0
        }

        photoGroups[targetIndex].photoItems.append(item)
        photoGroups[targetIndex].isExpanded = true
        selectedGroupID = photoGroups[targetIndex].id
        startLoadingAssets(for: item, url: normalizedURL)
        if selectedItems.isEmpty || targetGroupID != nil {
            selectedItems = [item.id]
            lastSelectedID = item.id
            schedulePreviewRegeneration(delayNanoseconds: 0)
        }
        saveWorkspace()
    }

    private func removePhoto(_ item: PhotoItem) {
        guard let groupIndex = groupIndex(containing: item.id) else { return }
        photoGroups[groupIndex].photoItems.removeAll { $0.id == item.id }
        refreshSelectionAfterPhotoMutation(preferredGroupID: selectedGroupID)
    }

    private func removePhotoSelection(startingWith item: PhotoItem) {
        if selectedItems.count > 1, selectedItems.contains(item.id) {
            deleteSelectedPhotos()
            return
        }

        removePhoto(item)
    }

    private func deleteSelectedPhotos() {
        guard !selectedItems.isEmpty else { return }
        let itemIDsToDelete = selectedItems

        for groupIndex in photoGroups.indices {
            photoGroups[groupIndex].photoItems.removeAll { itemIDsToDelete.contains($0.id) }
        }

        selectedItems.removeAll()
        lastSelectedID = nil
        refreshSelectionAfterPhotoMutation(preferredGroupID: selectedGroupID)
    }

    private func refreshSelectionAfterPhotoMutation(preferredGroupID: UUID? = nil) {
        let remainingItemIDs = Set(allPhotoItems.map(\.id))
        selectedItems = selectedItems.intersection(remainingItemIDs)

        if let lastSelectedID, !remainingItemIDs.contains(lastSelectedID) {
            self.lastSelectedID = nil
        }

        if let preferredGroupID,
           photoGroups.contains(where: { $0.id == preferredGroupID }) {
            selectedGroupID = preferredGroupID
        } else if let selectedGroupID,
                  !photoGroups.contains(where: { $0.id == selectedGroupID }) {
            self.selectedGroupID = photoGroups.first?.id
        } else if selectedGroupID == nil {
            selectedGroupID = photoGroups.first?.id
        }

        guard let selectedGroup else {
            selectedItems.removeAll()
            lastSelectedID = nil
            previewImage = nil
            saveWorkspace()
            schedulePreviewRegeneration(delayNanoseconds: 0)
            return
        }

        if let lastSelectedID,
           selectedItems.contains(lastSelectedID),
           selectedGroup.photoItems.contains(where: { $0.id == lastSelectedID }) {
            saveWorkspace()
            schedulePreviewRegeneration(delayNanoseconds: 0)
            return
        }

        if let selectedItem = selectedGroup.photoItems.first(where: { selectedItems.contains($0.id) }) {
            lastSelectedID = selectedItem.id
        } else if let firstItem = selectedGroup.photoItems.first {
            selectedItems = [firstItem.id]
            lastSelectedID = firstItem.id
        } else {
            selectedItems.removeAll()
            lastSelectedID = nil
            previewImage = nil
        }

        saveWorkspace()
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    private func clearPhotos() {
        guard !allPhotoItems.isEmpty else { return }
        lastClearedSnapshot = captureClearUndoSnapshot()
        for index in photoGroups.indices {
            photoGroups[index].photoItems.removeAll()
        }
        selectedItems.removeAll()
        lastSelectedID = nil
        previewImage = nil
        saveWorkspace()
    }

    private func undoClearPhotos() {
        guard let snapshot = lastClearedSnapshot else { return }
        lastClearedSnapshot = nil
        restore(from: snapshot)
    }

    private func selectItem(_ item: PhotoItem, modifiers: NSEvent.ModifierFlags) {
        if let groupIndex = groupIndex(containing: item.id) {
            selectedGroupID = photoGroups[groupIndex].id
        }

        if modifiers.contains(.command) {
            if selectedItems.contains(item.id) {
                selectedItems.remove(item.id)
                if lastSelectedID == item.id { lastSelectedID = nil }
            } else {
                selectedItems.insert(item.id)
                lastSelectedID = item.id
            }
        } else if modifiers.contains(.shift), let anchorID = lastSelectedID,
                  let anchorIdx = allPhotoItems.firstIndex(where: { $0.id == anchorID }),
                  let targetIdx = allPhotoItems.firstIndex(where: { $0.id == item.id }) {
            let start = min(anchorIdx, targetIdx)
            let end = max(anchorIdx, targetIdx)
            for i in start...end {
                selectedItems.insert(allPhotoItems[i].id)
            }
            lastSelectedID = item.id
        } else {
            selectedItems = [item.id]
            lastSelectedID = item.id
        }
        if selectedItems.isEmpty {
            previewImage = nil
        }
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    @MainActor
    private func schedulePreviewRegeneration(delayNanoseconds: UInt64 = 33_000_000) {
        previewScheduleTask?.cancel()

        previewScheduleTask = Task { @MainActor in
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            guard !Task.isCancelled else { return }
            regeneratePreview()
        }
    }

    @MainActor
    private func regeneratePreview() {
        guard let item = currentPreviewItem else {
            previewImage = nil
            isGeneratingPreview = false
            return 
        }
        
        previewTask?.cancel()
        
        let (options, bgOptions) = buildOptions(for: settings.editorConfiguration)
        if let bg = item.cachedBackground,
           item.cachedBackgroundOptions == bgOptions {
            previewImage = NSImage(
                cgImage: bg,
                size: NSSize(width: bg.width, height: bg.height)
            )
            isGeneratingPreview = false
            return
        }

        isGeneratingPreview = true
        
        // Fast path: use cached downscaled image (no disk I/O)
        if let cg = item.cachedPreviewImage,
           item.cachedExifInfo != nil,
           let orient = item.cachedOrientation,
           let size = item.cachedOrientedSize {
            let capturedCG = cg
            let capturedOrient = orient
            let capturedSize = size
            
            previewTask = Task.detached {
                guard !Task.isCancelled else { return }
                
                let lay = ImageProcessor.calculateLayout(imageWidth: capturedSize.width, imageHeight: capturedSize.height, options: options)
                do {
                    let bg = try ImageProcessor.renderBackground(cgImage: capturedCG, orientation: capturedOrient, layout: lay, options: options)
                    let ns = NSImage(cgImage: bg, size: NSSize(width: bg.width, height: bg.height))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        item.cachedBackground = bg
                        item.cachedBackgroundOptions = bgOptions
                        self.previewImage = ns
                        self.isGeneratingPreview = false
                    }
                } catch {
                    await MainActor.run { if !Task.isCancelled { self.isGeneratingPreview = false } }
                }
            }
            return
        }
        
        // Slow path fallback: read from disk (first time before cache is ready)
        let inputURL = item.url
        previewTask = Task.detached {
            guard !Task.isCancelled else { return }
            
            guard let data = PhotoItem.loadPreviewData(from: inputURL, maxDim: CGFloat(await self.previewMaxDim)) else {
                await MainActor.run { if !Task.isCancelled { self.isGeneratingPreview = false } }
                return
            }
            let (cg, exif, orient, ow, oh) = data
            
            // Cache for future use
            await MainActor.run {
                item.cachedPreviewImage = cg
                item.cachedExifInfo = exif
                item.cachedOrientation = orient
                item.cachedOrientedSize = (ow, oh)
            }
            
            let lay = ImageProcessor.calculateLayout(imageWidth: ow, imageHeight: oh, options: options)
            do {
                let bg = try ImageProcessor.renderBackground(cgImage: cg, orientation: orient, layout: lay, options: options)
                let ns = NSImage(cgImage: bg, size: NSSize(width: bg.width, height: bg.height))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    item.cachedBackground = bg
                    item.cachedBackgroundOptions = bgOptions
                    self.previewImage = ns
                    self.isGeneratingPreview = false
                }
            } catch {
                await MainActor.run { if !Task.isCancelled { self.isGeneratingPreview = false } }
            }
        }
    }
    
    private func invalidatePreviewCache() {
        for item in allPhotoItems {
            item.cachedPreviewImage = nil
            item.cachedExifInfo = nil
            item.cachedOrientation = nil
            item.cachedOrientedSize = nil
            item.cachedBackground = nil
            item.cachedBackgroundOptions = nil
        }
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    private func requestExport(scope: ExportScope) {
        guard !isProcessing else { return }

        switch scope {
        case .selected:
            guard !selectedItems.isEmpty else { return }
        case .all:
            guard !allPhotoItems.isEmpty else { return }
        }

        activeExportScope = scope
    }

    private func exportItemCount(for scope: ExportScope) -> Int {
        switch scope {
        case .selected:
            return selectedItems.count
        case .all:
            return allPhotoItems.count
        }
    }

    private func confirmExport(_ scope: ExportScope) {
        activeExportScope = nil

        let exportItems = exportItems(for: scope)
        guard !exportItems.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false

        guard panel.runModal() == .OK, let outputDirectory = panel.url else { return }

        let exportSettings = currentExportSettings
        isProcessing = true

        Task.detached {
            for exportItem in exportItems {
                let item = exportItem.item
                await MainActor.run { item.status = .processing }
                let outputURL = await MainActor.run {
                    self.outputURL(for: item, in: outputDirectory, exportSettings: exportSettings)
                }
                do {
                    let options = await MainActor.run { self.buildOptions(for: exportItem.state.configuration).0 }
                    try ImageProcessor.process(
                        inputURL: item.url,
                        outputURL: outputURL,
                        options: options,
                        exportSettings: exportSettings
                    )
                    await MainActor.run { item.status = .completed; item.resultURL = outputURL }
                }
                catch { await MainActor.run { item.status = .failed(error.localizedDescription) } }
            }
            await MainActor.run { isProcessing = false }
        }
    }

    private func exportItems(for scope: ExportScope) -> [(item: PhotoItem, state: FrameSettingsState)] {
        switch scope {
        case .selected:
            return photoGroups.flatMap { group in
                group.photoItems
                    .filter { selectedItems.contains($0.id) }
                    .map { (item: $0, state: group.settingsState) }
            }
        case .all:
            return photoGroups.flatMap { group in
                group.photoItems.map { (item: $0, state: group.settingsState) }
            }
        }
    }

    private func outputURL(for item: PhotoItem, in directory: URL, exportSettings: ExportSettings) -> URL {
        let baseName = item.url.deletingPathExtension().lastPathComponent
        let prefix = sanitizedFilenamePrefix(exportSettings.filenamePrefix)
        let fileName = "\(prefix)\(baseName).\(exportSettings.format.fileExtension)"
        return directory.appendingPathComponent(fileName)
    }

    private func sanitizedFilenamePrefix(_ prefix: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return prefix.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private func previewPreset(_ preset: Preset?) {
        if let preset {
            if presetPreviewOriginalState == nil {
                presetPreviewOriginalState = settings.state
            }
            guard presetPreviewID != preset.id else { return }
            presetPreviewID = preset.id
            isApplyingGroupSettings = true
            settings.apply(preset: preset)
            isApplyingGroupSettings = false
            schedulePreviewRegeneration(delayNanoseconds: 0)
            return
        }

        guard let originalState = presetPreviewOriginalState else { return }
        presetPreviewOriginalState = nil
        presetPreviewID = nil
        isApplyingGroupSettings = true
        settings.apply(state: originalState)
        isApplyingGroupSettings = false
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    private func applyPresetToSelectedGroup(_ preset: Preset) {
        presetPreviewOriginalState = nil
        presetPreviewID = nil

        let state = FrameSettingsState(configuration: preset.configuration)
        isApplyingGroupSettings = true
        settings.apply(state: state)
        isApplyingGroupSettings = false

        if let index = resolvedSelectedGroupIndex {
            photoGroups[index].settingsState = state
            saveWorkspace()
        }
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    @MainActor
    private func buildOptions(for configuration: FrameConfiguration) -> (ImageProcessor.Options, BackgroundOptions) {
        let fNS = NSColor(configuration.colorValue)
        let fc = fNS.usingColorSpace(.sRGB) ?? fNS
        let fcComponents = (r: fc.redComponent, g: fc.greenComponent, b: fc.blueComponent, a: fc.alphaComponent)
        let borderNS = NSColor(configuration.photoBorderColorValue)
        let border = borderNS.usingColorSpace(.sRGB) ?? borderNS
        let borderComponents = (r: border.redComponent, g: border.greenComponent, b: border.blueComponent, a: border.alphaComponent)
        
        let bgOptions = BackgroundOptions(
            frameColor: fcComponents,
            photoBorderEnabled: configuration.photoBorderEnabled,
            photoBorderColor: borderComponents,
            photoBorderWidthPercent: configuration.photoBorderWidthPercent,
            paddingRatio: configuration.paddingRatio,
            photoVOffset: configuration.photoVOffset,
            photoHOffset: configuration.photoHOffset,
            effectiveRatio: configuration.effectiveRatio,
            previewMaxDim: previewMaxDim
        )
        
        let processedLayers = configuration.textLayers.map { layer in
            let c = NSColor(layer.textColor).usingColorSpace(.sRGB) ?? NSColor.gray
            return ImageProcessor.TextLayerOptions(
                id: layer.id,
                textTemplate: layer.textTemplate,
                fontName: layer.fontName,
                fontSizePercent: layer.fontSizePercent,
                textColorComponents: (r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent),
                hOffset: layer.hOffset,
                vOffset: layer.vOffset,
                hAlignment: layer.hAlignment,
                isVisible: layer.isVisible
            )
        }
        
        let options = ImageProcessor.Options(
            effectiveRatio: configuration.effectiveRatio,
            frameColorComponents: fcComponents,
            photoBorderEnabled: configuration.photoBorderEnabled,
            photoBorderColorComponents: borderComponents,
            photoBorderWidthPercent: configuration.photoBorderWidthPercent,
            paddingRatio: configuration.paddingRatio,
            photoVOffset: configuration.photoVOffset,
            photoHOffset: configuration.photoHOffset,
            innerPadding: configuration.innerPadding,
            textLayers: processedLayers
        )
        
        return (options, bgOptions)
    }

    @MainActor
    private var currentPreviewTextLayers: [ImageProcessor.PreviewTextLayer] {
        guard let item = currentPreviewItem,
              let exif = item.cachedExifInfo,
              let size = item.cachedOrientedSize,
              previewImage != nil else {
            return []
        }

        let (options, _) = buildOptions(for: settings.editorConfiguration)
        let layout = ImageProcessor.calculateLayout(
            imageWidth: size.width,
            imageHeight: size.height,
            options: options
        )
        return ImageProcessor.previewTextLayers(
            exifInfo: exif,
            layout: layout,
            options: options
        )
    }
}
