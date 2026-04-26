import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content View

struct ContentView: View {
    private enum FocusPane: Hashable {
        case photoList
    }

    private enum PreviewMode: String, Identifiable {
        case item
        case slideshow

        var id: String { rawValue }
    }

    private struct ClearUndoSnapshot {
        let photoGroups: [PhotoGroup]
        let selectedGroupID: UUID?
        let selectedItems: Set<UUID>
        let lastSelectedID: UUID?
    }

    private struct SlideshowExportGroup {
        let group: PhotoGroup
        let items: [PhotoItem]
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
    @State private var previewVideoComposition: AVVideoComposition?
    @State private var previewVideoCompositionSignature = ""
    @State private var previewSlideshowURL: URL?
    @State private var slideshowPreviewIsPlaying = true
    @State private var isGeneratingPreview = false
    @State private var previewScheduleTask: Task<Void, Never>? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    @State private var previewMode: PreviewMode = .item
    @State private var isApplyingGroupSettings = false
    @State private var isApplyingGroupSlideshowSettings = false
    @State private var isRestoringWorkspace = false
    @State private var hasRestoredWorkspace = false
    @State private var lastClearedSnapshot: ClearUndoSnapshot? = nil
    @FocusState private var focusedPane: FocusPane?
    
    @AppStorage("userPresets") private var presetsData: Data = Data()
    @AppStorage("workspaceData") private var workspaceData: Data = Data()
    @AppStorage("workspaceBackupData") private var workspaceBackupData: Data = Data()
    @AppStorage("previewMaxDim") private var previewMaxDim: Double = 600
    @AppStorage("itemRowScale") private var itemRowScale = 1.0
    @AppStorage("exportFormat") private var exportFormatRaw = ExportFormat.jpeg.rawValue
    @AppStorage("lastStillExportFormat") private var lastStillExportFormatRaw = ExportFormat.jpeg.rawValue
    @AppStorage("exportJPEGQuality") private var exportJPEGQuality = 0.95
    @AppStorage("exportSizePreset") private var exportSizePresetRaw = ExportSizePreset.original.rawValue
    @AppStorage("exportCustomLongEdge") private var exportCustomLongEdge = 3000
    @AppStorage("exportFilenamePrefix") private var exportFilenamePrefix = "framed_"
    @AppStorage("exportCopyMetadata") private var exportCopyMetadata = true
    @AppStorage("exportSecondsPerPhoto") private var exportSecondsPerPhoto = 2.0
    @AppStorage("exportVideoDurationMode") private var exportVideoDurationModeRaw = SlideshowVideoDurationMode.original.rawValue
    @AppStorage("exportAudioBookmarkData") private var exportAudioBookmarkData: Data = Data()
    @AppStorage("exportAudioDisplayName") private var exportAudioDisplayName = ""
    @AppStorage("exportIncludeOriginalVideoAudio") private var exportIncludeOriginalVideoAudio = true
    @AppStorage("exportOriginalVideoAudioVolume") private var exportOriginalVideoAudioVolume = 1.0
    @AppStorage("exportBackgroundAudioVolume") private var exportBackgroundAudioVolume = 1.0
    @AppStorage("defaultAudioDirectoryPath") private var defaultAudioDirectoryPath = ""
    @AppStorage("exportFadeInEnabled") private var exportFadeInEnabled = true
    @AppStorage("exportFadeInDuration") private var exportFadeInDuration = 0.5
    @AppStorage("exportFadeOutEnabled") private var exportFadeOutEnabled = true
    @AppStorage("exportFadeOutDuration") private var exportFadeOutDuration = 1.0
    @AppStorage("fullscreenSlideshowAutoAdvanceGroups") private var fullscreenSlideshowAutoAdvanceGroups = false
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
    @State private var showingWorkspaceRecoveryAlert = false
    @State private var workspaceRecoveryMessage = ""
    @State private var workspaceAutoSavePaused = false
    @State private var showingResetWorkspaceAlert = false
    @State private var showingGroupSettingsTransferAlert = false
    @State private var groupSettingsTransferAlertTitle = ""
    @State private var groupSettingsTransferAlertMessage = ""
    @State private var fullscreenSlideshowWindowController: NSWindowController?
    @State private var fullscreenSlideshowCloseObserver: NSObjectProtocol?
    @State private var fullscreenSlideshowCurrentGroupID: UUID?
    @State private var fullscreenSlideshowPreparingNextGroup = false
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

    private var expandedPhotoItems: [PhotoItem] {
        photoGroups.flatMap { group in
            group.isExpanded ? group.photoItems : []
        }
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

    private var selectedGroupSlideshowItems: [PhotoItem] {
        selectedGroup?.photoItems ?? []
    }

    private var canPreviewSlideshow: Bool {
        !selectedGroupSlideshowItems.isEmpty
    }

    private var isSlideshowExportMode: Bool {
        previewMode == .slideshow
    }

    private var currentGroupExportCount: Int {
        selectedGroupSlideshowItems.count
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
        nonmutating set {
            exportFormatRaw = newValue.rawValue
            if newValue != .slideshowVideo {
                lastStillExportFormatRaw = newValue.rawValue
            }
        }
    }

    private var lastStillExportFormat: ExportFormat {
        get {
            let format = ExportFormat(rawValue: lastStillExportFormatRaw) ?? .jpeg
            return format == .slideshowVideo ? .jpeg : format
        }
        nonmutating set {
            guard newValue != .slideshowVideo else { return }
            lastStillExportFormatRaw = newValue.rawValue
        }
    }

    private var exportSizePreset: ExportSizePreset {
        get { ExportSizePreset(rawValue: exportSizePresetRaw) ?? .original }
        nonmutating set { exportSizePresetRaw = newValue.rawValue }
    }

    private var exportVideoDurationMode: SlideshowVideoDurationMode {
        get { SlideshowVideoDurationMode(rawValue: exportVideoDurationModeRaw) ?? .original }
        nonmutating set { exportVideoDurationModeRaw = newValue.rawValue }
    }

    private var currentExportSettings: ExportSettings {
        ExportSettings(
            format: exportFormat,
            jpegQuality: exportJPEGQuality,
            sizePreset: exportSizePreset,
            customLongEdge: exportCustomLongEdge,
            filenamePrefix: exportFilenamePrefix,
            copyMetadata: exportCopyMetadata,
            secondsPerPhoto: max(exportSecondsPerPhoto, 0.1),
            videoDurationMode: exportVideoDurationMode,
            audioBookmarkData: exportAudioBookmarkData.isEmpty ? nil : exportAudioBookmarkData,
            audioDisplayName: exportAudioDisplayName.isEmpty ? nil : exportAudioDisplayName,
            includeOriginalVideoAudio: exportIncludeOriginalVideoAudio,
            originalVideoAudioVolume: min(max(exportOriginalVideoAudioVolume, 0), 1),
            backgroundAudioVolume: min(max(exportBackgroundAudioVolume, 0), 1),
            fadeInEnabled: exportFadeInEnabled,
            fadeInDuration: max(exportFadeInDuration, 0),
            fadeOutEnabled: exportFadeOutEnabled,
            fadeOutDuration: max(exportFadeOutDuration, 0)
        )
    }

    private var currentGroupSlideshowSettings: SlideshowSettings {
        SlideshowSettings(
            secondsPerPhoto: max(exportSecondsPerPhoto, 0.1),
            videoDurationMode: exportVideoDurationMode,
            audioBookmarkData: exportAudioBookmarkData.isEmpty ? nil : exportAudioBookmarkData,
            audioDisplayName: exportAudioDisplayName.isEmpty ? nil : exportAudioDisplayName,
            includeOriginalVideoAudio: exportIncludeOriginalVideoAudio,
            originalVideoAudioVolume: min(max(exportOriginalVideoAudioVolume, 0), 1),
            backgroundAudioVolume: min(max(exportBackgroundAudioVolume, 0), 1),
            fadeInEnabled: exportFadeInEnabled,
            fadeInDuration: max(exportFadeInDuration, 0),
            fadeOutEnabled: exportFadeOutEnabled,
            fadeOutDuration: max(exportFadeOutDuration, 0)
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

    private var exportVideoDurationModeBinding: Binding<SlideshowVideoDurationMode> {
        Binding(
            get: { exportVideoDurationMode },
            set: { exportVideoDurationMode = $0 }
        )
    }

    private var slideshowPreviewContainsVideo: Bool {
        selectedGroup?.photoItems.contains(where: { $0.mediaKind.isVideo }) == true
    }

    @ViewBuilder
    private var slideshowPreviewSettingsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if slideshowPreviewContainsVideo {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center, spacing: 10) {
                        Text(L10n.slideshowVideoDurationMode(language))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                        Picker("", selection: Binding(
                            get: { exportVideoDurationMode },
                            set: {
                                exportVideoDurationMode = $0
                                schedulePreviewRegeneration(delayNanoseconds: 0)
                            }
                        )) {
                            ForEach(SlideshowVideoDurationMode.allCases) { mode in
                                Text(mode.title(language)).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text(slideshowPreviewContainsVideo ? L10n.slideshowSecondsPerItem(language) : L10n.slideshowSecondsPerPhoto(language))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                        TextField("", value: $exportSecondsPerPhoto, format: .number.precision(.fractionLength(1...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 68)
                            .onChange(of: exportSecondsPerPhoto) {
                                exportSecondsPerPhoto = max(exportSecondsPerPhoto, 0.1)
                                schedulePreviewRegeneration(delayNanoseconds: 150_000_000)
                            }
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Text(L10n.slideshowSecondsPerPhoto(language))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                    TextField("", value: $exportSecondsPerPhoto, format: .number.precision(.fractionLength(1...2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 68)
                        .onChange(of: exportSecondsPerPhoto) {
                            exportSecondsPerPhoto = max(exportSecondsPerPhoto, 0.1)
                            schedulePreviewRegeneration(delayNanoseconds: 150_000_000)
                        }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Button(L10n.chooseAudio(language), action: chooseExportAudio)
                    .controlSize(.small)
                Button(L10n.clearAudio(language), action: clearExportAudio)
                    .controlSize(.small)
                    .opacity(exportAudioDisplayName.isEmpty ? 0 : 1)
                    .disabled(exportAudioDisplayName.isEmpty)
                Text(exportAudioDisplayName.isEmpty ? L10n.noAudioSelected(language) : exportAudioDisplayName)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.55))
                    .lineLimit(1)
                HStack(spacing: 10) {
                    Text(L10n.backgroundAudioVolume(language))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.65))
                    Slider(value: $exportBackgroundAudioVolume, in: 0...1, step: 0.05)
                        .frame(width: 150)
                        .onChange(of: exportBackgroundAudioVolume) {
                            schedulePreviewRegeneration(delayNanoseconds: 0)
                        }
                    Text("\(Int((exportBackgroundAudioVolume * 100).rounded()))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 42, alignment: .trailing)
                }
                .opacity(exportAudioDisplayName.isEmpty ? 0 : 1)
                .allowsHitTesting(!exportAudioDisplayName.isEmpty)
                Spacer(minLength: 0)
            }

            if slideshowPreviewContainsVideo {
                HStack(alignment: .center, spacing: 10) {
                    Toggle(L10n.useOriginalVideoAudio(language), isOn: $exportIncludeOriginalVideoAudio)
                        .toggleStyle(.checkbox)
                        .onChange(of: exportIncludeOriginalVideoAudio) {
                            schedulePreviewRegeneration(delayNanoseconds: 0)
                        }
                    if exportIncludeOriginalVideoAudio {
                        Text(L10n.originalVideoAudioVolume(language))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.65))
                        Slider(value: $exportOriginalVideoAudioVolume, in: 0...1, step: 0.05)
                            .frame(maxWidth: 170)
                            .onChange(of: exportOriginalVideoAudioVolume) {
                                schedulePreviewRegeneration(delayNanoseconds: 0)
                            }
                        Text("\(Int((exportOriginalVideoAudioVolume * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.white.opacity(0.55))
                            .frame(width: 42, alignment: .trailing)
                    }
                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Toggle(L10n.fadeIn(language), isOn: $exportFadeInEnabled)
                        .toggleStyle(.checkbox)
                        .onChange(of: exportFadeInEnabled) {
                            schedulePreviewRegeneration(delayNanoseconds: 0)
                        }
                    if exportFadeInEnabled {
                        TextField("", value: $exportFadeInDuration, format: .number.precision(.fractionLength(1...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .onChange(of: exportFadeInDuration) {
                                exportFadeInDuration = max(exportFadeInDuration, 0)
                                schedulePreviewRegeneration(delayNanoseconds: 150_000_000)
                            }
                    }
                }
                HStack(spacing: 8) {
                    Toggle(L10n.fadeOut(language), isOn: $exportFadeOutEnabled)
                        .toggleStyle(.checkbox)
                        .onChange(of: exportFadeOutEnabled) {
                            schedulePreviewRegeneration(delayNanoseconds: 0)
                        }
                    if exportFadeOutEnabled {
                        TextField("", value: $exportFadeOutDuration, format: .number.precision(.fractionLength(1...2)))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 64)
                            .onChange(of: exportFadeOutDuration) {
                                exportFadeOutDuration = max(exportFadeOutDuration, 0)
                                schedulePreviewRegeneration(delayNanoseconds: 150_000_000)
                            }
                    }
                }
                Spacer()
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(theme.panelFill.opacity(0.45))
    }

    @MainActor
    private func applyPreviewVideoComposition(
        for url: URL,
        item: PhotoItem,
        options: ImageProcessor.Options
    ) async {
        let composition = await VideoProcessor.makePreviewVideoComposition(
            for: url,
            options: options
        )
        guard !Task.isCancelled else { return }
        previewVideoComposition = composition
        previewVideoCompositionSignature = previewVideoSignature(
            for: item,
            configuration: settings.editorConfiguration
        )
    }

    private func exportSheetItems(for scope: ExportScope) -> [PhotoItem] {
        if isSlideshowExportMode {
            return slideshowGroups(for: scope).flatMap(\.items)
        }

        return exportItems(for: scope).map(\.item)
    }

    @ViewBuilder
    private func exportSettingsSheet(for scope: ExportScope) -> some View {
        let scopedItems = exportSheetItems(for: scope)

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
            secondsPerPhoto: $exportSecondsPerPhoto,
            videoDurationMode: exportVideoDurationModeBinding,
            audioDisplayName: exportAudioDisplayName.isEmpty ? nil : exportAudioDisplayName,
            includeOriginalVideoAudio: $exportIncludeOriginalVideoAudio,
            originalVideoAudioVolume: $exportOriginalVideoAudioVolume,
            backgroundAudioVolume: $exportBackgroundAudioVolume,
            fadeInEnabled: $exportFadeInEnabled,
            fadeInDuration: $exportFadeInDuration,
            fadeOutEnabled: $exportFadeOutEnabled,
            fadeOutDuration: $exportFadeOutDuration,
            isSlideshowWorkflow: isSlideshowExportMode,
            containsImageItems: scopedItems.contains(where: { !$0.mediaKind.isVideo }),
            containsVideoItems: scopedItems.contains(where: { $0.mediaKind.isVideo }),
            onChooseAudio: chooseExportAudio,
            onClearAudio: clearExportAudio,
            onConfirm: { confirmExport(scope) }
        )
    }

    private var rootView: some View {
        ZStack {
            backgroundGradient
            mainHStack
        }
        .tint(theme.accent)
    }

    private var lifecycleConfiguredView: some View {
        rootView
            .onAppear {
                restoreWorkspaceIfNeeded()
                if selectedGroupID == nil {
                    selectedGroupID = photoGroups.first?.id
                }
                loadSelectedGroupSettings()
            }
            .onChange(of: selectedGroupID) {
                loadSelectedGroupSettings()
                loadSelectedGroupSlideshowSettings()
            }
            .onChange(of: settings.state) {
                persistSettingsToSelectedGroup()
            }
            .onChange(of: exportSecondsPerPhoto) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportVideoDurationModeRaw) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportAudioBookmarkData) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportAudioDisplayName) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportIncludeOriginalVideoAudio) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportOriginalVideoAudioVolume) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportBackgroundAudioVolume) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportFadeInEnabled) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportFadeInDuration) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportFadeOutEnabled) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: exportFadeOutDuration) {
                persistSlideshowSettingsToSelectedGroup()
            }
            .onChange(of: settings.editorConfiguration.backgroundPreviewSignature) {
                schedulePreviewRegeneration()
            }
    }

    private var presentationConfiguredView: some View {
        lifecycleConfiguredView
            .onReceive(NotificationCenter.default.publisher(for: .photoFrameExportAllGroupSettings)) { _ in
                exportAllGroupSettings()
            }
            .onReceive(NotificationCenter.default.publisher(for: .photoFrameImportAllGroupSettings)) { _ in
                importAllGroupSettings()
            }
            .sheet(item: $activeExportScope) { scope in
                exportSettingsSheet(for: scope)
            }
            .alert(L10n.workspaceRecoveryTitle(language), isPresented: $showingWorkspaceRecoveryAlert) {
                Button(L10n.ok(language)) { }
            } message: {
                Text(workspaceRecoveryMessage)
            }
            .alert(groupSettingsTransferAlertTitle, isPresented: $showingGroupSettingsTransferAlert) {
                Button(L10n.ok(language)) { }
            } message: {
                Text(groupSettingsTransferAlertMessage)
            }
            .alert(L10n.resetWorkspaceTitle(language), isPresented: $showingResetWorkspaceAlert) {
                Button(L10n.resetWorkspace(language), role: .destructive) {
                    resetWorkspaceAndResumeAutoSave()
                }
                Button(L10n.cancel(language), role: .cancel) { }
            } message: {
                Text(L10n.resetWorkspaceMessage(language))
            }
    }

    var body: some View {
        presentationConfiguredView
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
            if workspaceAutoSavePaused {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.workspaceAutoSavePaused(language))
                        .font(.caption2)
                        .foregroundColor(.yellow.opacity(0.9))

                    HStack(spacing: 8) {
                        Button(L10n.resumeAutoSave(language), action: resumeWorkspaceAutoSave)
                            .buttonStyle(.plain)
                            .foregroundColor(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(theme.elevatedFill, in: Capsule())

                        Button(L10n.resetWorkspace(language)) {
                            showingResetWorkspaceAlert = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.18), in: Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

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

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.compress.vertical")
                        .font(.caption)
                        .foregroundColor(theme.accent)
                    Text(L10n.itemRowSize(language))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                    Spacer()
                    Text(L10n.compact(language))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.35))
                    Text(L10n.comfortable(language))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.35))
                }
                Slider(value: $itemRowScale, in: 0.75...1.4, step: 0.05)
                    .tint(theme.accent)
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
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focusedPane, equals: .photoList)
        .onTapGesture {
            focusedPane = .photoList
        }
        .onMoveCommand(perform: movePhotoSelection)
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
                Text(processSelectedTitle).font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(theme.elevatedFill)
            .foregroundColor(.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isProcessing || processSelectedDisabled)
        .opacity(isProcessing || processSelectedDisabled ? 0.5 : 1.0)
    }

    private var processAllButton: some View {
        Button(action: { requestExport(scope: .all) }) {
            HStack(spacing: 6) {
                if isProcessing { ProgressView().controlSize(.small).tint(.white) }
                else { Image(systemName: "wand.and.stars").font(.system(size: 12)) }
                Text(isProcessing ? L10n.processing(language) : processAllTitle).font(.system(size: 12, weight: .semibold))
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

    private var processSelectedTitle: String {
        if isSlideshowExportMode {
            return L10n.exportCurrentGroup(currentGroupExportCount, language)
        }
        return L10n.processSelected(selectedItems.count, language)
    }

    private var processAllTitle: String {
        isSlideshowExportMode ? L10n.exportAllGroups(language) : L10n.processAll(language)
    }

    private var processSelectedDisabled: Bool {
        if isSlideshowExportMode {
            return currentGroupExportCount == 0
        }
        return selectedItems.isEmpty
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
                        .onDrop(of: [.text], isTargeted: nil) { providers in
                            handlePhotoRowDrop(
                                providers: providers,
                                targetGroupID: group.id,
                                targetItemID: item.id
                            )
                        }
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
                if canPreviewSlideshow {
                    Picker("", selection: $previewMode) {
                        Text(L10n.previewModePhoto(language)).tag(PreviewMode.item)
                        Text(L10n.previewModeSlideshow(language)).tag(PreviewMode.slideshow)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .onChange(of: previewMode) {
                        if previewMode == .slideshow {
                            selectedItems.removeAll()
                            slideshowPreviewIsPlaying = true
                        }
                        schedulePreviewRegeneration(delayNanoseconds: 0)
                    }
                    if previewMode == .slideshow {
                        Text(L10n.slideshowPreviewStopToEditHint(language))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(2)
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                }
                Spacer()
                if previewMode == .slideshow {
                    Button {
                        slideshowPreviewIsPlaying.toggle()
                    } label: {
                        Image(systemName: slideshowPreviewIsPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(previewSlideshowURL == nil ? 0.3 : 0.75))
                    }
                    .buttonStyle(.plain)
                    .disabled(previewSlideshowURL == nil)
                    .help(slideshowPreviewIsPlaying ? L10n.stopSlideshow(language) : L10n.playSlideshow(language))
                    if let selectedGroup {
                        Text(selectedGroup.displayName(language))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                    if previewSlideshowURL != nil {
                        Button(action: openFullscreenSlideshowPreview) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.fullscreenPreview(language))
                    }
                } else if let item = currentPreviewItem {
                    Text(item.filename).font(.caption).foregroundColor(.white.opacity(0.4)).lineLimit(1)
                }
                Button(action: clearPreviewSelection) { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.3)) }.buttonStyle(.plain)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider().background(theme.divider)
            ZStack {
                theme.previewSurface
                if previewMode == .slideshow {
                    if let previewSlideshowURL {
                        ZStack {
                            SlideshowVideoPreviewCanvas(
                                url: previewSlideshowURL,
                                isMuted: fullscreenSlideshowWindowController != nil || (
                                    exportAudioDisplayName.isEmpty &&
                                    !(exportIncludeOriginalVideoAudio && (selectedGroup?.photoItems.contains(where: { $0.mediaKind.isVideo }) == true))
                                ),
                                isPlaying: slideshowPreviewIsPlaying
                            )
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    slideshowPreviewIsPlaying.toggle()
                                }
                        }
                        .padding(20)
                    } else if !canPreviewSlideshow {
                        Text(L10n.slideshowPreviewNeedsPhotos(language))
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    } else if isGeneratingPreview {
                        VStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white.opacity(0.8))
                            Text(L10n.preparingSlideshowPreview(language))
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.35))
                        }
                    }
                } else if let preview = previewImage,
                          let previewItem = currentPreviewItem {
                    Group {
                        if previewItem.mediaKind.isVideo,
                           let layout = currentPreviewLayout {
                            LiveVideoPreviewCanvas(
                                backgroundImage: preview,
                                videoURL: previewItem.url,
                                videoComposition: previewVideoComposition,
                                compositionSignature: previewVideoCompositionSignature,
                                imageRect: layout.imageRect,
                                textLayers: currentPreviewTextLayers
                            )
                        } else {
                            LivePreviewCanvas(
                                image: preview,
                                textLayers: currentPreviewTextLayers
                            )
                        }
                    }
                    .padding(20)
                    .shadow(
                        color: previewItem.mediaKind.isVideo ? .clear : .black.opacity(0.5),
                        radius: previewItem.mediaKind.isVideo ? 0 : 20,
                        x: 0,
                        y: previewItem.mediaKind.isVideo ? 0 : 8
                    )
                } else if !isGeneratingPreview {
                    Text(L10n.selectPhotoToPreview(language)).font(.caption).foregroundColor(.white.opacity(0.3))
                }
            }
            if previewMode == .slideshow {
                Divider().background(theme.divider)
                slideshowPreviewSettingsPanel
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
                LUTSettingsSection(configuration: settings.editorConfigurationBinding, language: language)
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
                            Text(L10n.preview2K(language)).tag(2048.0)
                            Text(L10n.preview4K(language)).tag(3840.0)
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
        guard !hasRestoredWorkspace else { return }
        hasRestoredWorkspace = true
        restoreWorkspace()
    }

    private func restoreWorkspace() {
        if workspaceData.isEmpty {
            if let backupSnapshot = decodeWorkspace(from: workspaceBackupData) {
                workspaceRecoveryMessage = L10n.workspacePrimaryRestoreFailed(language)
                showingWorkspaceRecoveryAlert = true
                workspaceData = workspaceBackupData
                applyRestoredWorkspace(backupSnapshot)
            }
            return
        }

        if let snapshot = decodeWorkspace(from: workspaceData) {
            applyRestoredWorkspace(snapshot)
            return
        }

        if let backupSnapshot = decodeWorkspace(from: workspaceBackupData) {
            workspaceRecoveryMessage = L10n.workspacePrimaryRestoreFailed(language)
            showingWorkspaceRecoveryAlert = true
            workspaceData = workspaceBackupData
            applyRestoredWorkspace(backupSnapshot)
            return
        }

        workspaceAutoSavePaused = true
        workspaceRecoveryMessage = L10n.workspaceRestoreFailedNoBackup(language)
        showingWorkspaceRecoveryAlert = true
    }

    private func resumeWorkspaceAutoSave() {
        workspaceAutoSavePaused = false
        workspaceRecoveryMessage = L10n.workspaceAutoSaveResumed(language)
        showingWorkspaceRecoveryAlert = true
        saveWorkspace()
    }

    @MainActor
    private func resetWorkspaceAndResumeAutoSave() {
        previewTask?.cancel()
        previewScheduleTask?.cancel()
        clearSlideshowPreview()
        previewImage = nil
        previewVideoComposition = nil
        previewVideoCompositionSignature = ""
        photoGroups = [.ungrouped()]
        selectedGroupID = photoGroups.first?.id
        selectedItems.removeAll()
        lastSelectedID = nil
        lastClearedSnapshot = nil
        settings.apply(state: FrameSettingsState())
        exportAudioBookmarkData = Data()
        exportAudioDisplayName = ""
        exportSecondsPerPhoto = 2.0
        exportFadeInEnabled = true
        exportFadeInDuration = 0.5
        exportFadeOutEnabled = true
        exportFadeOutDuration = 1.0
        workspaceData = Data()
        workspaceBackupData = Data()
        workspaceAutoSavePaused = false
        loadSelectedGroupSettings()
        loadSelectedGroupSlideshowSettings()
        saveWorkspace()
    }

    private func decodeWorkspace(from data: Data) -> PersistedWorkspace? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(PersistedWorkspace.self, from: data)
    }

    private func applyRestoredWorkspace(_ snapshot: PersistedWorkspace) {
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
                slideshowSettings: persistedGroup.slideshowSettings ?? SlideshowSettings(),
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
        loadSelectedGroupSlideshowSettings()

        for group in photoGroups {
            for item in group.photoItems {
                startLoadingAssets(for: item, url: item.url)
            }
        }

        isRestoringWorkspace = false
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
        guard !isRestoringWorkspace, !workspaceAutoSavePaused else { return }

        let snapshot = PersistedWorkspace(
            selectedGroupID: selectedGroupID,
            groups: photoGroups.map { group in
                PersistedPhotoGroup(
                    id: group.id,
                    name: group.name,
                    isDefaultGroup: group.isDefaultGroup,
                    isExpanded: group.isExpanded,
                    settingsState: group.settingsState,
                    slideshowSettings: group.slideshowSettings,
                    photoPaths: group.photoItems.map { $0.url.path }
                )
            }
        )

        guard let encoded = try? JSONEncoder().encode(snapshot) else { return }
        if !workspaceData.isEmpty, workspaceData != encoded {
            workspaceBackupData = workspaceData
        }
        workspaceData = encoded
    }

    private func startLoadingAssets(for item: PhotoItem, url: URL) {
        Task.detached {
            if item.mediaKind.isVideo {
                let maxDim = await self.previewMaxDim
                let previewData = try? await VideoProcessor.loadPreviewData(
                    from: url,
                    maxDim: CGFloat(max(maxDim, 240))
                )

                await MainActor.run {
                    if let previewData {
                        item.thumbnail = NSImage(
                            cgImage: previewData.posterImage,
                            size: NSSize(
                                width: previewData.posterImage.width,
                                height: previewData.posterImage.height
                            )
                        )
                        item.cachedPreviewImage = previewData.posterImage
                        item.cachedExifInfo = previewData.exifInfo
                        item.cachedOrientation = .up
                        item.cachedOrientedSize = previewData.orientedSize
                        item.cachedVideoDuration = previewData.durationSeconds
                    }
                }
                return
            }

            let thumb = ImageProcessor.generateThumbnail(for: url)
            let maxDim = await self.previewMaxDim
            let previewData = PhotoItem.loadImagePreviewData(from: url, maxDim: CGFloat(maxDim))
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

    private func loadSelectedGroupSlideshowSettings() {
        guard let index = resolvedSelectedGroupIndex else { return }
        let targetSettings = photoGroups[index].slideshowSettings
        isApplyingGroupSlideshowSettings = true
        exportSecondsPerPhoto = max(targetSettings.secondsPerPhoto, 0.1)
        exportVideoDurationMode = targetSettings.videoDurationMode
        exportAudioBookmarkData = targetSettings.audioBookmarkData ?? Data()
        exportAudioDisplayName = targetSettings.audioDisplayName ?? ""
        exportIncludeOriginalVideoAudio = targetSettings.includeOriginalVideoAudio
        exportOriginalVideoAudioVolume = min(max(targetSettings.originalVideoAudioVolume, 0), 1)
        exportBackgroundAudioVolume = min(max(targetSettings.backgroundAudioVolume, 0), 1)
        exportFadeInEnabled = targetSettings.fadeInEnabled
        exportFadeInDuration = max(targetSettings.fadeInDuration, 0)
        exportFadeOutEnabled = targetSettings.fadeOutEnabled
        exportFadeOutDuration = max(targetSettings.fadeOutDuration, 0)
        isApplyingGroupSlideshowSettings = false
    }

    private func persistSlideshowSettingsToSelectedGroup() {
        guard !isApplyingGroupSlideshowSettings,
              let index = resolvedSelectedGroupIndex else { return }

        let currentSettings = currentGroupSlideshowSettings
        guard photoGroups[index].slideshowSettings != currentSettings else { return }
        photoGroups[index].slideshowSettings = currentSettings
        saveWorkspace()
    }

    private func addGroup() {
        let groupName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty else { return }

        let group = PhotoGroup(
            name: groupName,
            settingsState: settings.state,
            slideshowSettings: currentGroupSlideshowSettings
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

        focusedPane = .photoList
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

    private func movePhotos(withIDs itemIDs: Set<UUID>, before targetItemID: UUID, in targetGroupID: UUID) {
        guard let targetIndex = photoGroups.firstIndex(where: { $0.id == targetGroupID }),
              let originalTargetPosition = photoGroups[targetIndex].photoItems.firstIndex(where: { $0.id == targetItemID }) else {
            return
        }

        var movedItems: [PhotoItem] = []
        for index in photoGroups.indices {
            let extractedItems = photoGroups[index].photoItems.filter { itemIDs.contains($0.id) }
            if !extractedItems.isEmpty {
                movedItems.append(contentsOf: extractedItems)
                photoGroups[index].photoItems.removeAll { itemIDs.contains($0.id) }
            }
        }

        guard !movedItems.isEmpty else { return }

        let insertionIndex = min(originalTargetPosition, photoGroups[targetIndex].photoItems.count)
        photoGroups[targetIndex].photoItems.insert(contentsOf: movedItems, at: insertionIndex)
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

    private func handlePhotoRowDrop(
        providers: [NSItemProvider],
        targetGroupID: UUID,
        targetItemID: UUID
    ) -> Bool {
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
                guard !ids.isEmpty, !ids.contains(targetItemID) else { return }

                Task { @MainActor in
                    movePhotos(withIDs: ids, before: targetItemID, in: targetGroupID)
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
                let mediaURLs = urls
                    .map(\.standardizedFileURL)
                    .filter { MediaKind.from(url: $0) != nil }
                guard !mediaURLs.isEmpty else { return }

                Task { @MainActor in
                    for url in mediaURLs {
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
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = MediaKind.supportedContentTypes
        if panel.runModal() == .OK { panel.urls.forEach { addPhoto(url: $0) } }
    }

    private func addPhoto(url: URL, to targetGroupID: UUID? = nil) {
        let normalizedURL = url.standardizedFileURL
        guard MediaKind.from(url: normalizedURL) != nil else { return }
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
        focusedPane = .photoList
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

    private func movePhotoSelection(_ direction: MoveCommandDirection) {
        let step: Int
        switch direction {
        case .up:
            step = -1
        case .down:
            step = 1
        default:
            return
        }

        guard !allPhotoItems.isEmpty else { return }

        let currentID = lastSelectedID ?? selectedItems.first
        let visibleItems = expandedPhotoItems
        let items: [PhotoItem]

        if visibleItems.isEmpty {
            items = allPhotoItems
        } else if let currentID,
                  visibleItems.contains(where: { $0.id == currentID }) {
            items = visibleItems
        } else {
            items = allPhotoItems
        }

        guard !items.isEmpty else { return }

        let currentIndex: Int
        if let currentID,
           let index = items.firstIndex(where: { $0.id == currentID }) {
            currentIndex = index
        } else {
            currentIndex = step > 0 ? -1 : items.count
        }

        let nextIndex = min(max(currentIndex + step, 0), items.count - 1)
        let nextItem = items[nextIndex]

        selectedItems = [nextItem.id]
        lastSelectedID = nextItem.id
        if let groupIndex = groupIndex(containing: nextItem.id) {
            selectedGroupID = photoGroups[groupIndex].id
        }
        saveWorkspace()
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
        if previewMode == .slideshow {
            regenerateSlideshowPreview()
            return
        }

        guard let item = currentPreviewItem else {
            previewImage = nil
            isGeneratingPreview = false
            return 
        }
        
        previewTask?.cancel()
        
        let (options, bgOptions) = buildOptions(for: settings.editorConfiguration)
        if let bg = item.cachedBackground,
           item.cachedBackgroundOptions == bgOptions {
            if item.mediaKind.isVideo {
                previewTask = Task {
                    await applyPreviewVideoComposition(for: item.url, item: item, options: options)
                }
            } else {
                previewVideoComposition = nil
                previewVideoCompositionSignature = ""
            }
            previewImage = NSImage(
                cgImage: bg,
                size: NSSize(width: bg.width, height: bg.height)
            )
            isGeneratingPreview = false
            return
        }

        isGeneratingPreview = true

        if item.mediaKind.isVideo {
            let inputURL = item.url
            if let size = item.cachedOrientedSize {
                let capturedSize = size

                previewTask = Task.detached {
                    guard !Task.isCancelled else { return }

                    let layout = ImageProcessor.calculateLayout(
                        imageWidth: capturedSize.width,
                        imageHeight: capturedSize.height,
                        options: options
                    )

                    do {
                        let bg = try ImageProcessor.renderFrameBackground(layout: layout, options: options)
                        let composition = await VideoProcessor.makePreviewVideoComposition(
                            for: inputURL,
                            options: options
                        )
                        let ns = NSImage(cgImage: bg, size: NSSize(width: bg.width, height: bg.height))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            item.cachedBackground = bg
                            item.cachedBackgroundOptions = bgOptions
                            self.previewVideoComposition = composition
                            self.previewVideoCompositionSignature = self.previewVideoSignature(
                                for: item,
                                configuration: self.settings.editorConfiguration
                            )
                            self.previewImage = ns
                            self.isGeneratingPreview = false
                        }
                    } catch {
                        await MainActor.run {
                            if !Task.isCancelled {
                                self.isGeneratingPreview = false
                            }
                        }
                    }
                }
                return
            }

            previewTask = Task.detached {
                guard !Task.isCancelled else { return }

                let maxDim = await self.previewMaxDim
                guard let data = try? await VideoProcessor.loadPreviewData(
                    from: inputURL,
                    maxDim: CGFloat(maxDim)
                ) else {
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.isGeneratingPreview = false
                        }
                    }
                    return
                }

                await MainActor.run {
                    item.cachedPreviewImage = data.posterImage
                    item.cachedExifInfo = data.exifInfo
                    item.cachedOrientation = .up
                    item.cachedOrientedSize = data.orientedSize
                    item.cachedVideoDuration = data.durationSeconds
                }

                let layout = ImageProcessor.calculateLayout(
                    imageWidth: data.orientedSize.width,
                    imageHeight: data.orientedSize.height,
                    options: options
                )

                do {
                    let bg = try ImageProcessor.renderFrameBackground(layout: layout, options: options)
                    let composition = await VideoProcessor.makePreviewVideoComposition(
                        for: inputURL,
                        options: options
                    )
                    let ns = NSImage(cgImage: bg, size: NSSize(width: bg.width, height: bg.height))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        item.cachedBackground = bg
                        item.cachedBackgroundOptions = bgOptions
                        self.previewVideoComposition = composition
                        self.previewVideoCompositionSignature = self.previewVideoSignature(
                            for: item,
                            configuration: self.settings.editorConfiguration
                        )
                        self.previewImage = ns
                        self.isGeneratingPreview = false
                    }
                } catch {
                    await MainActor.run {
                        if !Task.isCancelled {
                            self.isGeneratingPreview = false
                        }
                    }
                }
            }
            return
        }
        previewVideoComposition = nil
        previewVideoCompositionSignature = ""
        
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
            
            guard let data = PhotoItem.loadImagePreviewData(from: inputURL, maxDim: CGFloat(await self.previewMaxDim)) else {
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

    @MainActor
    private func regenerateSlideshowPreview() {
        previewTask?.cancel()
        previewImage = nil
        clearSlideshowPreview()

        guard canPreviewSlideshow, let selectedGroup else {
            isGeneratingPreview = false
            return
        }

        isGeneratingPreview = true
        let items = selectedGroup.photoItems
        let exportSettings = currentExportSettings
        let options = buildOptions(for: selectedGroup.settingsState.configuration).0
        let outputURL = temporaryPreviewSlideshowURL()

        previewTask = Task.detached {
            do {
                try await SlideshowVideoProcessor.processPreview(
                    items: items,
                    outputURL: outputURL,
                    options: options,
                    exportSettings: exportSettings,
                    previewMaxDimension: await self.previewMaxDim
                )
                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: outputURL)
                    return
                }
                await MainActor.run {
                    self.replaceSlideshowPreviewURL(with: outputURL)
                    self.isGeneratingPreview = false
                }
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                await MainActor.run {
                    if !Task.isCancelled {
                        self.clearSlideshowPreview()
                        self.isGeneratingPreview = false
                    }
                }
            }
        }
    }
    
    private func invalidatePreviewCache() {
        for item in allPhotoItems {
            item.cachedPreviewImage = nil
            item.cachedExifInfo = nil
            item.cachedOrientation = nil
            item.cachedOrientedSize = nil
            item.cachedVideoDuration = nil
            item.cachedBackground = nil
            item.cachedBackgroundOptions = nil
        }
        previewVideoComposition = nil
        previewVideoCompositionSignature = ""
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    @MainActor
    private func replaceSlideshowPreviewURL(with url: URL) {
        if previewSlideshowURL != url, let previewSlideshowURL {
            try? FileManager.default.removeItem(at: previewSlideshowURL)
        }
        previewSlideshowURL = url
        slideshowPreviewIsPlaying = true
        fullscreenSlideshowCurrentGroupID = selectedGroupID
        fullscreenSlideshowPreparingNextGroup = false
        if fullscreenSlideshowWindowController != nil {
            openFullscreenSlideshowPreview()
        }
    }

    @MainActor
    private func clearSlideshowPreview() {
        if let previewSlideshowURL {
            try? FileManager.default.removeItem(at: previewSlideshowURL)
        }
        previewSlideshowURL = nil
        slideshowPreviewIsPlaying = true
        if fullscreenSlideshowWindowController != nil {
            openFullscreenSlideshowPreview()
        }
    }

    private func temporaryPreviewSlideshowURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoFrame-preview-\(UUID().uuidString)")
            .appendingPathExtension("mov")
    }

    private func requestExport(scope: ExportScope) {
        guard !isProcessing else { return }

        if isSlideshowExportMode {
            exportFormat = .slideshowVideo
        } else if exportFormat == .slideshowVideo {
            exportFormat = lastStillExportFormat
        }

        if isSlideshowExportMode {
            switch scope {
            case .selected:
                guard currentGroupExportCount > 0 else { return }
            case .all:
                guard photoGroups.contains(where: { !$0.photoItems.isEmpty }) else { return }
            }
        } else {
            switch scope {
            case .selected:
                guard !selectedItems.isEmpty else { return }
            case .all:
                guard !allPhotoItems.isEmpty else { return }
            }
        }

        activeExportScope = scope
    }

    private func exportItemCount(for scope: ExportScope) -> Int {
        if isSlideshowExportMode {
            switch scope {
            case .selected:
                return currentGroupExportCount
            case .all:
                return photoGroups.reduce(0) { partialResult, group in
                    partialResult + group.photoItems.count
                }
            }
        }

        switch scope {
        case .selected:
            return selectedItems.count
        case .all:
            return allPhotoItems.count
        }
    }

    private func confirmExport(_ scope: ExportScope) {
        activeExportScope = nil

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.canChooseFiles = false
        panel.prompt = L10n.exportAction(language)
        panel.message = L10n.exportDestination(language)

        guard panel.runModal() == .OK, let outputDirectory = panel.url else { return }

        let exportSettings = currentExportSettings
        let exportItems = exportItems(for: scope)
        let slideshowGroups = exportSettings.format == .slideshowVideo
            ? slideshowGroups(for: scope)
            : []
        if exportSettings.format == .slideshowVideo {
            guard !slideshowGroups.isEmpty else { return }
        } else {
            guard !exportItems.isEmpty else { return }
        }
        isProcessing = true

        Task.detached {
            if exportSettings.format == .slideshowVideo {
                for slideshowGroup in slideshowGroups {
                    let items = slideshowGroup.items
                    await MainActor.run {
                        for item in items {
                            item.status = .processing
                        }
                    }

                    let outputURL = await MainActor.run {
                        self.outputURL(
                            forGroup: slideshowGroup.group,
                            in: outputDirectory,
                            exportSettings: exportSettings
                        )
                    }

                    do {
                        let options = await MainActor.run {
                            self.buildOptions(for: slideshowGroup.group.settingsState.configuration).0
                        }
                        try await SlideshowVideoProcessor.process(
                            items: items,
                            outputURL: outputURL,
                            options: options,
                            exportSettings: exportSettings
                        )
                        await MainActor.run {
                            for item in items {
                                item.status = .completed
                                item.resultURL = outputURL
                            }
                        }
                    } catch {
                        await MainActor.run {
                            for item in items {
                                item.status = .failed(error.localizedDescription)
                            }
                        }
                    }
                }
            } else {
                for exportItem in exportItems {
                    let item = exportItem.item
                    await MainActor.run { item.status = .processing }
                    let outputURL = await MainActor.run {
                        self.outputURL(for: item, in: outputDirectory, exportSettings: exportSettings)
                    }
                    do {
                        let options = await MainActor.run { self.buildOptions(for: exportItem.state.configuration).0 }
                        if item.mediaKind.isVideo {
                            try await VideoProcessor.process(
                                inputURL: item.url,
                                outputURL: outputURL,
                                options: options,
                                exportSettings: exportSettings
                            )
                        } else {
                            try ImageProcessor.process(
                                inputURL: item.url,
                                outputURL: outputURL,
                                options: options,
                                exportSettings: exportSettings
                            )
                        }
                        await MainActor.run { item.status = .completed; item.resultURL = outputURL }
                    }
                    catch { await MainActor.run { item.status = .failed(error.localizedDescription) } }
                }
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
        let fileExtension = item.mediaKind.isVideo ? "mov" : exportSettings.format.fileExtension
        let fileName = "\(prefix)\(baseName).\(fileExtension)"
        return directory.appendingPathComponent(fileName)
    }

    private func outputURL(forGroup group: PhotoGroup, in directory: URL, exportSettings: ExportSettings) -> URL {
        let rawName = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = rawName.isEmpty ? "ungrouped" : rawName
        let prefix = sanitizedFilenamePrefix(exportSettings.filenamePrefix)
        let sanitizedBaseName = sanitizedFilenamePrefix(baseName)
        let fileName = "\(prefix)\(sanitizedBaseName).\(exportSettings.format.fileExtension)"
        return directory.appendingPathComponent(fileName)
    }

    private func sanitizedFilenamePrefix(_ prefix: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        return prefix.components(separatedBy: invalidCharacters).joined(separator: "-")
    }

    private func slideshowGroups(for scope: ExportScope) -> [SlideshowExportGroup] {
        if isSlideshowExportMode {
            switch scope {
            case .selected:
                guard let selectedGroup else { return [] }
                guard !selectedGroup.photoItems.isEmpty else { return [] }
                return [SlideshowExportGroup(group: selectedGroup, items: selectedGroup.photoItems)]
            case .all:
                return photoGroups.compactMap { group in
                    guard !group.photoItems.isEmpty else { return nil }
                    return SlideshowExportGroup(group: group, items: group.photoItems)
                }
            }
        }

        return photoGroups.compactMap { group -> SlideshowExportGroup? in
            let items: [PhotoItem]
            switch scope {
            case .selected:
                items = group.photoItems.filter {
                    selectedItems.contains($0.id)
                }
            case .all:
                items = group.photoItems
            }

            guard !items.isEmpty else { return nil }
            return SlideshowExportGroup(group: group, items: items)
        }
    }

    private func chooseExportAudio() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        if !defaultAudioDirectoryPath.isEmpty {
            let url = URL(fileURLWithPath: defaultAudioDirectoryPath)
            if FileManager.default.fileExists(atPath: url.path) {
                panel.directoryURL = url
            }
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let bookmarkData = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            exportAudioBookmarkData = bookmarkData
            exportAudioDisplayName = url.lastPathComponent
            if previewMode == .slideshow {
                schedulePreviewRegeneration(delayNanoseconds: 0)
            }
        } catch {
            exportAudioBookmarkData = Data()
            exportAudioDisplayName = ""
        }
    }

    private func clearExportAudio() {
        exportAudioBookmarkData = Data()
        exportAudioDisplayName = ""
        if previewMode == .slideshow {
            schedulePreviewRegeneration(delayNanoseconds: 0)
        }
    }

    private func exportGroupSettings(_ group: PhotoGroup) {
        let transfer = GroupSettingsTransfer(
            name: group.name,
            settingsState: group.settingsState,
            slideshowSettings: group.slideshowSettings
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        let suggestedName = PresetCodec.sanitizedFileNameComponent(from: group.displayName(language))
        panel.nameFieldStringValue = "\(suggestedName)-GroupSettings.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let exportData = try PresetCodec.encodeGroupSettingsTransfer(transfer)
            try exportData.write(to: url, options: .atomic)
        } catch {
            presentGroupSettingsTransferError(
                title: L10n.groupSettingsExportFailed(language),
                message: error.localizedDescription
            )
        }
    }

    private func exportAllGroupSettings() {
        let transfer = GroupSettingsCollectionTransfer(
            groups: photoGroups.map { group in
                GroupSettingsTransfer(
                    name: group.name,
                    settingsState: group.settingsState,
                    slideshowSettings: group.slideshowSettings
                )
            }
        )

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "PhotoFrame-GroupSettings.json"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let exportData = try PresetCodec.encodeGroupSettingsCollectionTransfer(transfer)
            try exportData.write(to: url, options: .atomic)
        } catch {
            presentGroupSettingsTransferError(
                title: L10n.groupSettingsExportFailed(language),
                message: error.localizedDescription
            )
        }
    }

    private func importGroupSettings(into groupID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let transfer = try PresetCodec.decodeGroupSettingsTransfer(from: data)
            applyGroupSettingsTransfer(transfer, to: groupID)
        } catch {
            presentGroupSettingsTransferError(
                title: L10n.groupSettingsImportFailed(language),
                message: groupSettingsTransferErrorMessage(for: error)
            )
        }
    }

    private func importAllGroupSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let transfer = try PresetCodec.decodeGroupSettingsCollectionTransfer(from: data)
            applyAllGroupSettingsTransfer(transfer)
        } catch {
            presentGroupSettingsTransferError(
                title: L10n.groupSettingsImportFailed(language),
                message: groupSettingsTransferErrorMessage(for: error)
            )
        }
    }

    private func applyGroupSettingsTransfer(_ transfer: GroupSettingsTransfer, to groupID: UUID) {
        guard let index = photoGroups.firstIndex(where: { $0.id == groupID }) else { return }
        photoGroups[index].settingsState = transfer.settingsState
        photoGroups[index].slideshowSettings = transfer.slideshowSettings

        if selectedGroupID == groupID {
            loadSelectedGroupSettings()
            loadSelectedGroupSlideshowSettings()
            schedulePreviewRegeneration(delayNanoseconds: 0)
        }

        saveWorkspace()
    }

    private func applyAllGroupSettingsTransfer(_ transfer: GroupSettingsCollectionTransfer) {
        guard !transfer.groups.isEmpty else { return }

        for groupTransfer in transfer.groups {
            let normalizedName = normalizedGroupName(groupTransfer.name)
            if let index = photoGroups.firstIndex(where: { normalizedGroupName($0.name) == normalizedName }) {
                photoGroups[index].settingsState = groupTransfer.settingsState
                photoGroups[index].slideshowSettings = groupTransfer.slideshowSettings
            } else {
                photoGroups.append(
                    PhotoGroup(
                        name: groupTransfer.name,
                        isDefaultGroup: false,
                        isExpanded: true,
                        settingsState: groupTransfer.settingsState,
                        slideshowSettings: groupTransfer.slideshowSettings,
                        photoItems: []
                    )
                )
            }
        }

        loadSelectedGroupSettings()
        loadSelectedGroupSlideshowSettings()
        schedulePreviewRegeneration(delayNanoseconds: 0)
        saveWorkspace()
    }

    private func normalizedGroupName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func presentGroupSettingsTransferError(title: String, message: String) {
        groupSettingsTransferAlertTitle = title
        groupSettingsTransferAlertMessage = message
        showingGroupSettingsTransferAlert = true
    }

    private func groupSettingsTransferErrorMessage(for error: Error) -> String {
        if case PresetCodecError.invalidPresetFile = error {
            return L10n.invalidGroupSettingsFile(language)
        }
        return error.localizedDescription
    }

    private func clearPreviewSelection() {
        selectedItems.removeAll()
        previewImage = nil
        if previewMode == .slideshow {
            clearSlideshowPreview()
        }
    }

    private func openFullscreenSlideshowPreview() {
        let onPlaybackEnded: (() -> Void)? = fullscreenSlideshowAutoAdvanceGroups
            ? { handleFullscreenSlideshowPlaybackEnded() }
            : nil
        let onClose: () -> Void = { closeFullscreenSlideshowPreview() }

        let contentView: FullscreenSlideshowPreview = FullscreenSlideshowPreview(
            videoURL: previewSlideshowURL,
            isMuted: exportAudioDisplayName.isEmpty,
            loops: !fullscreenSlideshowAutoAdvanceGroups,
            language: language,
            isPreparingNextGroup: fullscreenSlideshowPreparingNextGroup,
            onPlaybackEnded: onPlaybackEnded,
            onClose: onClose
        )
        let hostingController = NSHostingController(rootView: contentView)

        let window: NSWindow
        let controller: NSWindowController
        if let existingController = fullscreenSlideshowWindowController,
           let existingWindow = existingController.window {
            existingWindow.contentViewController = hostingController
            window = existingWindow
            controller = existingController
        } else {
            window = NSWindow(
                contentRect: NSScreen.main?.frame ?? .init(x: 0, y: 0, width: 1280, height: 720),
                styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.collectionBehavior = [.fullScreenPrimary, .fullScreenAllowsTiling]
            window.contentViewController = hostingController
            controller = NSWindowController(window: window)
            fullscreenSlideshowWindowController = controller
            fullscreenSlideshowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    fullscreenSlideshowWindowController = nil
                    fullscreenSlideshowCurrentGroupID = nil
                    fullscreenSlideshowPreparingNextGroup = false
                    if let observer = fullscreenSlideshowCloseObserver {
                        NotificationCenter.default.removeObserver(observer)
                        fullscreenSlideshowCloseObserver = nil
                    }
                }
            }
        }

        fullscreenSlideshowCurrentGroupID = selectedGroupID
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }

    private func closeFullscreenSlideshowPreview() {
        guard let window = fullscreenSlideshowWindowController?.window else { return }
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        window.close()
        fullscreenSlideshowWindowController = nil
        fullscreenSlideshowCurrentGroupID = nil
        fullscreenSlideshowPreparingNextGroup = false
        if let observer = fullscreenSlideshowCloseObserver {
            NotificationCenter.default.removeObserver(observer)
            fullscreenSlideshowCloseObserver = nil
        }
    }

    private func handleFullscreenSlideshowPlaybackEnded() {
        guard fullscreenSlideshowAutoAdvanceGroups else { return }
        advanceFullscreenSlideshowToNextGroup()
    }

    @MainActor
    private func advanceFullscreenSlideshowToNextGroup() {
        guard let currentGroupID = fullscreenSlideshowCurrentGroupID,
              let currentIndex = photoGroups.firstIndex(where: { $0.id == currentGroupID }),
              let nextIndex = nextSlideshowGroupIndex(after: currentIndex) else {
            return
        }

        fullscreenSlideshowPreparingNextGroup = true
        previewMode = .slideshow
        selectedGroupID = photoGroups[nextIndex].id
        selectedItems.removeAll()
        lastSelectedID = nil
        previewImage = nil
        saveWorkspace()
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    private func nextSlideshowGroupIndex(after currentIndex: Int) -> Int? {
        guard !photoGroups.isEmpty else { return nil }

        for offset in 1...photoGroups.count {
            let candidateIndex = (currentIndex + offset) % photoGroups.count
            if !photoGroups[candidateIndex].photoItems.isEmpty {
                return candidateIndex
            }
        }

        return nil
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
            previewMaxDim: previewMaxDim,
            lutConfiguration: configuration.lutConfiguration
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
            lutConfiguration: configuration.lutConfiguration.isEnabled && configuration.lutConfiguration.hasFileSelection
                ? configuration.lutConfiguration
                : nil,
            textLayers: processedLayers
        )
        
        return (options, bgOptions)
    }

    @MainActor
    private var currentPreviewLayout: ImageProcessor.Layout? {
        guard let item = currentPreviewItem,
              let size = item.cachedOrientedSize else {
            return nil
        }

        let (options, _) = buildOptions(for: settings.editorConfiguration)
        return ImageProcessor.calculateLayout(
            imageWidth: size.width,
            imageHeight: size.height,
            options: options
        )
    }

    @MainActor
    private var currentPreviewTextLayers: [ImageProcessor.PreviewTextLayer] {
        guard let item = currentPreviewItem,
              let exif = item.cachedExifInfo,
              let layout = currentPreviewLayout,
              previewImage != nil else {
            return []
        }

        let (options, _) = buildOptions(for: settings.editorConfiguration)
        return ImageProcessor.previewTextLayers(
            exifInfo: exif,
            layout: layout,
            options: options
        )
    }

    private func previewVideoSignature(for item: PhotoItem, configuration: FrameConfiguration) -> String {
        let lut = configuration.lutConfiguration
        return "\(item.id.uuidString)|\(lut.isEnabled)|\(lut.filePath)|\(lut.intensity)"
    }
}
