import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content View

struct ContentView: View {
    @AppStorage("appLanguage") private var appLanguageRaw = AppLanguage.english.rawValue
    @StateObject private var settings = FrameSettings()
    @State private var photoItems: [PhotoItem] = []
    @State private var isProcessing = false
    @State private var isDragTargeted = false
    @State private var selectedItems: Set<UUID> = []
    @State private var lastSelectedID: UUID? = nil
    @State private var previewImage: NSImage?
    @State private var isGeneratingPreview = false
    @State private var previewScheduleTask: Task<Void, Never>? = nil
    @State private var previewTask: Task<Void, Never>? = nil
    
    @AppStorage("userPresets") private var presetsData: Data = Data()
    @AppStorage("previewMaxDim") private var previewMaxDim: Double = 600
    @State private var showingPresetAlert = false
    @State private var newPresetName: String = ""
    @State private var showingRenamePresetAlert = false
    @State private var presetRenameTargetID: UUID? = nil
    @State private var renamePresetName: String = ""

    private var language: AppLanguage {
        AppLanguage(rawValue: appLanguageRaw) ?? .english
    }

    var body: some View {
        ZStack {
            backgroundGradient
            mainHStack
        }
        .onChange(of: settings.backgroundPreviewSignature) {
            schedulePreviewRegeneration()
        }
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(nsColor: NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 1)),
                Color(nsColor: NSColor(red: 0.12, green: 0.10, blue: 0.16, alpha: 1)),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var mainHStack: some View {
        HStack(spacing: 0) {
            fileListPanel
                .frame(minWidth: 220, idealWidth: !selectedItems.isEmpty ? 260 : 480, maxWidth: !selectedItems.isEmpty ? 300 : .infinity)

            if !selectedItems.isEmpty {
                Divider().background(Color.white.opacity(0.1))
                previewPanel.frame(minWidth: 300)
            }

            Divider().background(Color.white.opacity(0.1))
            settingsPanel.frame(width: 300)
        }
    }

    // MARK: - Panels

    private var fileListPanel: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.white.opacity(0.08))
            if photoItems.isEmpty { dropZone } else { photoList }
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "photo.artframe").font(.title2).foregroundStyle(.linearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing))
            Text("PhotoFrame").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundColor(.white)
            Spacer()
            if !photoItems.isEmpty {
                Button(action: clearPhotos) { Label(L10n.clear(language), systemImage: "trash").font(.caption) }
                    .buttonStyle(.plain).foregroundColor(.white.opacity(0.6)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        }.padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var dropZone: some View {
        VStack(spacing: 16) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 20).strokeBorder(isDragTargeted ? Color.blue : Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 2, dash: [8, 4]))
                    .background(RoundedRectangle(cornerRadius: 20).fill(isDragTargeted ? Color.blue.opacity(0.08) : Color.white.opacity(0.03)))
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.doc.fill").font(.system(size: 48)).foregroundStyle(.linearGradient(colors: [.purple.opacity(0.6), .blue.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    Text(L10n.dropJPEGFilesHere(language)).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: 400, maxHeight: 300)
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in handleDrop(providers: providers); return true }
            .onTapGesture { browseFiles() }
            Spacer()
        }.padding(24)
    }

    private var photoList: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 4) { ForEach(photoItems) { photoRow($0) } }.padding(8)
            }.onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in handleDrop(providers: providers); return true }
            Divider().background(Color.white.opacity(0.1))
            HStack {
                Button(action: browseFiles) { Image(systemName: "plus.circle.fill").font(.system(size: 16)) }.buttonStyle(.plain).foregroundColor(.white.opacity(0.5))
                Text(L10n.photoCount(photoItems.count, language)).font(.caption).foregroundColor(.white.opacity(0.5))
                Spacer()
                processButtons
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private var processButtons: some View {
        HStack(spacing: 12) {
            Button(action: processSelectedPhoto) {
                HStack(spacing: 6) {
                    Image(systemName: "selection.pin.in.out").font(.system(size: 12))
                    Text(L10n.processSelected(selectedItems.count, language)).font(.system(size: 12, weight: .semibold))
                }.padding(.horizontal, 14).padding(.vertical, 7).background(Color.white.opacity(0.1)).foregroundColor(.white).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(isProcessing || selectedItems.isEmpty).opacity(isProcessing || selectedItems.isEmpty ? 0.5 : 1.0)

            Button(action: processAllPhotos) {
                HStack(spacing: 6) {
                    if isProcessing { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "wand.and.stars").font(.system(size: 12)) }
                    Text(isProcessing ? L10n.processing(language) : L10n.processAll(language)).font(.system(size: 12, weight: .semibold))
                }.padding(.horizontal, 14).padding(.vertical, 7).background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)).foregroundColor(.white).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(isProcessing || photoItems.isEmpty).opacity(isProcessing ? 0.7 : 1.0)
        }
    }

    private func photoRow(_ item: PhotoItem) -> some View {
        let isSelected = selectedItems.contains(item.id)
        return Button(action: { selectItem(item, modifiers: NSEvent.modifierFlags) }) {
            HStack(spacing: 10) {
                Group {
                    if let thumb = item.thumbnail { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
                    else { Rectangle().fill(Color.white.opacity(0.05)).overlay(ProgressView().controlSize(.small)) }
                }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.9)).lineLimit(1)
                    Text(item.status.label(language)).font(.caption2).foregroundColor(statusColor(item.status))
                }
                Spacer()
            }.padding(8).contentShape(Rectangle())
        }
        .buttonStyle(.plain).background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Color.blue.opacity(0.2) : Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1))
        .overlay(alignment: .trailing) {
            Button(action: { removePhoto(item) }) { Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundColor(.white.opacity(0.3)).padding(8) }.buttonStyle(.plain)
        }
    }

    private func statusColor(_ status: ProcessingStatus) -> Color {
        switch status { case .pending: return .white.opacity(0.4); case .processing: return .blue; case .completed: return .green; case .failed: return .red }
    }

    private var previewPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "eye.fill").font(.caption).foregroundColor(.blue.opacity(0.8))
                Text(L10n.preview(language)).font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.8))
                Spacer()
                if let item = photoItems.first(where: { selectedItems.contains($0.id) }) { Text(item.filename).font(.caption).foregroundColor(.white.opacity(0.4)).lineLimit(1) }
                Button(action: { selectedItems.removeAll(); previewImage = nil }) { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.3)) }.buttonStyle(.plain)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider().background(Color.white.opacity(0.08))
            ZStack {
                Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
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
                    Text(L10n.settings(language)).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                    Spacer()
                    PresetMenu(
                        settings: settings,
                        presetsData: $presetsData,
                        showingAlert: $showingPresetAlert,
                        language: language,
                        onRenamePreset: beginRenamingPreset
                    )
                }
                
                AspectRatioSettings(settings: settings, language: language)
                AlignmentSettings(settings: settings, language: language)
                FrameColorSettings(settings: settings, language: language)
                TextLayersSettings(settings: settings, language: language)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Image(systemName: "square.dashed").font(.caption).foregroundColor(.blue.opacity(0.8)); Text(L10n.frameWidth(language)).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
                    HStack {
                        Slider(value: $settings.paddingRatio, in: 0.0...0.15, step: 0.01).tint(.blue)
                        NumericField(value: $settings.paddingRatio).frame(width: 50).font(.caption2)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "eye").font(.caption).foregroundColor(.blue.opacity(0.8))
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
        }.background(Color.white.opacity(0.03))
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
        var presets: [Preset] = []
        if let decoded = try? JSONDecoder().decode([Preset].self, from: presetsData) { presets = decoded }
        presets.append(settings.createPreset(name: presetName))
        if let encoded = try? JSONEncoder().encode(presets) { presetsData = encoded }
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

        var presets = (try? JSONDecoder().decode([Preset].self, from: presetsData)) ?? []
        guard let index = presets.firstIndex(where: { $0.id == targetID }) else {
            resetRenamePresetState()
            return
        }

        presets[index].name = presetName
        if let encoded = try? JSONEncoder().encode(presets) {
            presetsData = encoded
        }
        resetRenamePresetState()
    }

    private func resetRenamePresetState() {
        presetRenameTargetID = nil
        renamePresetName = ""
        showingRenamePresetAlert = false
    }

    // MARK: - Handlers

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil, isAbsolute: true) else { return }
                if ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) { Task { @MainActor in addPhoto(url: url) } }
            }
        }
    }

    private func browseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.allowedContentTypes = [UTType.jpeg]
        if panel.runModal() == .OK { panel.urls.forEach { addPhoto(url: $0) } }
    }

    private func addPhoto(url: URL) {
        guard !photoItems.contains(where: { $0.url == url }) else { return }
        let item = PhotoItem(url: url); photoItems.append(item)
        Task.detached {
            let thumb = ImageProcessor.generateThumbnail(for: url)
            // Pre-load and cache a downscaled image + EXIF for fast preview
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
        if selectedItems.isEmpty { selectItem(item, modifiers: []) }
    }

    private func removePhoto(_ item: PhotoItem) { photoItems.removeAll { $0.id == item.id }; selectedItems.remove(item.id); if selectedItems.isEmpty { previewImage = nil } }
    private func clearPhotos() { photoItems.removeAll(); selectedItems.removeAll(); previewImage = nil }
    private func selectItem(_ item: PhotoItem, modifiers: NSEvent.ModifierFlags) { 
        if modifiers.contains(.command) {
            if selectedItems.contains(item.id) {
                selectedItems.remove(item.id)
                if lastSelectedID == item.id { lastSelectedID = nil }
            } else {
                selectedItems.insert(item.id)
                lastSelectedID = item.id
            }
        } else if modifiers.contains(.shift), let anchorID = lastSelectedID,
                  let anchorIdx = photoItems.firstIndex(where: { $0.id == anchorID }),
                  let targetIdx = photoItems.firstIndex(where: { $0.id == item.id }) {
            let start = min(anchorIdx, targetIdx)
            let end = max(anchorIdx, targetIdx)
            for i in start...end {
                selectedItems.insert(photoItems[i].id)
            }
        } else {
            selectedItems = [item.id]
            lastSelectedID = item.id
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
        guard let item = photoItems.first(where: { selectedItems.contains($0.id) }) else { 
            previewImage = nil
            isGeneratingPreview = false
            return 
        }
        
        previewTask?.cancel()
        
        let (options, bgOptions) = buildOptions()
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
        for item in photoItems {
            item.cachedPreviewImage = nil
            item.cachedExifInfo = nil
            item.cachedOrientation = nil
            item.cachedOrientedSize = nil
            item.cachedBackground = nil
            item.cachedBackgroundOptions = nil
        }
        schedulePreviewRegeneration(delayNanoseconds: 0)
    }

    private func processAllPhotos() {
        guard !isProcessing else { return }; let p = NSOpenPanel(); p.canChooseDirectories = true; p.canCreateDirectories = true
        guard p.runModal() == .OK, let out = p.url else { return }; isProcessing = true; let (opt, _) = buildOptions()
        Task.detached {
            let items = await MainActor.run { photoItems }
            for item in items {
                await MainActor.run { item.status = .processing }; let ourl = out.appendingPathComponent("framed_\(item.filename)")
                do { try ImageProcessor.process(inputURL: item.url, outputURL: ourl, options: opt); await MainActor.run { item.status = .completed; item.resultURL = ourl } }
                catch { await MainActor.run { item.status = .failed(error.localizedDescription) } }
            }
            await MainActor.run { isProcessing = false }
        }
    }

    private func processSelectedPhoto() {
        guard !selectedItems.isEmpty && !isProcessing else { return }
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canCreateDirectories = true
        guard p.runModal() == .OK, let out = p.url else { return }
        isProcessing = true; let (opt, _) = buildOptions()
        Task.detached {
            let itemsToProcess = await MainActor.run { photoItems.filter { selectedItems.contains($0.id) } }
            for item in itemsToProcess {
                await MainActor.run { item.status = .processing }
                let ourl = out.appendingPathComponent("framed_\(item.filename)")
                do {
                    try ImageProcessor.process(inputURL: item.url, outputURL: ourl, options: opt)
                    await MainActor.run { item.status = .completed; item.resultURL = ourl }
                } catch {
                    await MainActor.run { item.status = .failed(error.localizedDescription) }
                }
            }
            await MainActor.run { isProcessing = false }
        }
    }

    @MainActor
    private func buildOptions() -> (ImageProcessor.Options, BackgroundOptions) {
        let fNS = NSColor(settings.frameColor)
        let fc = fNS.usingColorSpace(.sRGB) ?? fNS
        let fcComponents = (r: fc.redComponent, g: fc.greenComponent, b: fc.blueComponent, a: fc.alphaComponent)
        
        let bgOptions = BackgroundOptions(
            frameColor: fcComponents,
            paddingRatio: settings.paddingRatio,
            photoVOffset: settings.photoVOffset,
            photoHOffset: settings.photoHOffset,
            effectiveRatio: settings.effectiveRatio,
            previewMaxDim: previewMaxDim
        )
        
        let processedLayers = settings.textLayers.map { layer in
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
            effectiveRatio: settings.effectiveRatio, frameColorComponents: fcComponents,
            paddingRatio: settings.paddingRatio,
            photoVOffset: settings.photoVOffset, photoHOffset: settings.photoHOffset,
            innerPadding: settings.innerPadding,
            textLayers: processedLayers
        )
        
        return (options, bgOptions)
    }

    @MainActor
    private var currentPreviewTextLayers: [ImageProcessor.PreviewTextLayer] {
        guard let item = photoItems.first(where: { selectedItems.contains($0.id) }),
              let exif = item.cachedExifInfo,
              let size = item.cachedOrientedSize,
              previewImage != nil else {
            return []
        }

        let (options, _) = buildOptions()
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

// MARK: - Subviews

struct LivePreviewCanvas: View {
    let image: NSImage
    let textLayers: [ImageProcessor.PreviewTextLayer]

    var body: some View {
        GeometryReader { geometry in
            let sourceSize = CGSize(
                width: max(image.size.width, 1),
                height: max(image.size.height, 1)
            )
            let scale = min(
                geometry.size.width / sourceSize.width,
                geometry.size.height / sourceSize.height
            )
            let fittedSize = CGSize(
                width: sourceSize.width * scale,
                height: sourceSize.height * scale
            )
            let offset = CGPoint(
                x: (geometry.size.width - fittedSize.width) / 2.0,
                y: (geometry.size.height - fittedSize.height) / 2.0
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: fittedSize.width, height: fittedSize.height)

                ZStack(alignment: .topLeading) {
                    ForEach(textLayers) { layer in
                        Text(layer.text)
                            .font(.custom(layer.fontName, size: layer.fontSize))
                            .foregroundStyle(
                                Color(
                                    nsColor: NSColor(
                                        srgbRed: layer.textColorComponents.r,
                                        green: layer.textColorComponents.g,
                                        blue: layer.textColorComponents.b,
                                        alpha: layer.textColorComponents.a
                                    )
                                )
                            )
                            .fixedSize()
                            .position(
                                x: layer.origin.x + layer.size.width / 2.0,
                                y: sourceSize.height - layer.origin.y - layer.size.height / 2.0
                            )
                    }
                }
                .frame(width: sourceSize.width, height: sourceSize.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .allowsHitTesting(false)
            }
            .frame(width: fittedSize.width, height: fittedSize.height, alignment: .topLeading)
            .offset(x: offset.x, y: offset.y)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}

private enum NumericFieldFormatterCache {
    static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 3
        return formatter
    }()
}

struct NumericField<T: BinaryFloatingPoint>: View {
    @Binding var value: T
    @State private var text: String = ""

    private func formattedValue(_ value: T) -> String {
        NumericFieldFormatterCache.formatter.string(from: NSNumber(value: Double(value))) ?? ""
    }
    
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .onChange(of: text) { _, newValue in
                if let d = Double(newValue) { value = T(d) }
            }
            .onChange(of: value) { _, newValue in
                let formatted = formattedValue(newValue)
                if text != formatted {
                    text = formatted
                }
            }
            .onAppear {
                text = formattedValue(value)
            }
    }
}

struct DebouncedTextField: View {
    let placeholder: String
    @Binding var text: String
    @State private var draftText: String = ""
    @State private var task: Task<Void, Never>? = nil
    
    var body: some View {
        TextField(placeholder, text: $draftText)
            .textFieldStyle(.roundedBorder)
            .onChange(of: draftText) { _, newValue in
                task?.cancel()
                task = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    text = newValue
                }
            }
            .onChange(of: text) { _, newValue in
                if draftText != newValue {
                    draftText = newValue
                }
            }
            .onAppear {
                draftText = text
            }
    }
}

struct AspectRatioSettings: View {
    @ObservedObject var settings: FrameSettings
    let language: AppLanguage
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "aspectratio").font(.caption).foregroundColor(.blue.opacity(0.8)); Text(L10n.aspectRatio(language)).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(AspectRatio.allCases) { ratio in
                    Button(action: { settings.aspectRatio = ratio }) {
                        Text(ratio.title(language)).font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(settings.aspectRatio == ratio ? Color.blue.opacity(0.2) : Color.white.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(settings.aspectRatio == ratio ? Color.blue : Color.clear, lineWidth: 1))
                    }.buttonStyle(.plain).foregroundColor(settings.aspectRatio == ratio ? .white : .white.opacity(0.6))
                }
            }
            if settings.aspectRatio == .custom {
                HStack(spacing: 8) {
                    TextField("W", text: $settings.customWidth).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                    Text(":").foregroundColor(.white.opacity(0.5))
                    TextField("H", text: $settings.customHeight).textFieldStyle(.roundedBorder).multilineTextAlignment(.center)
                }.padding(.top, 4)
            }
        }
    }
}

struct AlignmentSettings: View {
    @ObservedObject var settings: FrameSettings
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "hand.tap.fill").font(.caption).foregroundColor(.blue.opacity(0.8)); Text(L10n.photoPosition(language)).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.vertical(language)).font(.caption2).foregroundColor(.white.opacity(0.4))
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                    Slider(value: $settings.photoVOffset, in: 0.0...1.0).tint(.blue)
                    NumericField(value: $settings.photoVOffset).frame(width: 45).font(.caption2)
                    Image(systemName: "arrow.down.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.horizontal(language)).font(.caption2).foregroundColor(.white.opacity(0.4))
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                    Slider(value: $settings.photoHOffset, in: 0.0...1.0).tint(.blue)
                    NumericField(value: $settings.photoHOffset).frame(width: 45).font(.caption2)
                    Image(systemName: "arrow.right.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }
}

struct FrameColorSettings: View {
    @ObservedObject var settings: FrameSettings
    let language: AppLanguage
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "paintpalette").font(.caption).foregroundColor(.blue.opacity(0.8)); Text(L10n.frameStyle(language)).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            HStack { Label(L10n.color(language), systemImage: "square").font(.caption2).foregroundColor(.white.opacity(0.4)); Spacer(); ColorPicker("", selection: $settings.frameColor).labelsHidden() }
        }
    }
}

struct TextLayersSettings: View {
    @ObservedObject var settings: FrameSettings
    let language: AppLanguage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "text.alignleft").font(.caption).foregroundColor(.blue.opacity(0.8)); Text(L10n.textLayers(language)).font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            
            ForEach($settings.textLayers) { $layer in
                TextLayerEditorRow(layer: $layer, language: language) {
                    if let idx = settings.textLayers.firstIndex(where: { $0.id == layer.id }) {
                        settings.textLayers.remove(at: idx)
                    }
                }
            }
            
            Button(action: {
                settings.textLayers.append(TextLayer(textTemplate: "{Camera} • {Lens}", fontName: "Helvetica Neue", fontSizePercent: 1.8, textColor: .gray, hOffset: 0.5, vOffset: 0.9, hAlignment: .center))
            }) {
                HStack { Image(systemName: "plus.circle.fill"); Text(L10n.addLayer(language)) }.frame(maxWidth: .infinity)
            }.buttonStyle(.plain).padding(8).background(Color.blue.opacity(0.2)).foregroundColor(.blue).cornerRadius(8)
            
            Text(L10n.tags(language)).font(.caption2).foregroundColor(.white.opacity(0.4)).padding(.top, 4)
        }
    }
}

struct TextLayerEditorRow: View {
    @AppStorage("fontSelectionDisplayMode") private var fontSelectionDisplayModeRaw = FontSelectionDisplayMode.compact.rawValue
    @Binding var layer: TextLayer
    let language: AppLanguage
    let onRemove: () -> Void

    private var fontSelectionDisplayMode: FontSelectionDisplayMode {
        FontSelectionDisplayMode(rawValue: fontSelectionDisplayModeRaw) ?? .compact
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                DebouncedTextField(placeholder: L10n.textTemplate(language), text: $layer.textTemplate).font(.system(size: 12))

                HStack {
                    Label(L10n.color(language), systemImage: "paintpalette").font(.caption2).foregroundColor(.white.opacity(0.4))
                    Spacer()
                    ColorPicker("", selection: $layer.textColor).labelsHidden()
                }

                if fontSelectionDisplayMode == .classic {
                    ClassicFontPicker(selection: $layer.fontName, language: language)
                } else {
                    SearchableFontPicker(selection: $layer.fontName, language: language)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.textSize(language)).font(.caption2).foregroundColor(.white.opacity(0.4))
                    HStack {
                        Slider(value: $layer.fontSizePercent, in: 0.5...5.0, step: 0.1).tint(.blue)
                        NumericField(value: $layer.fontSizePercent).frame(width: 45).font(.caption2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.textPosition(language)).font(.caption2).foregroundColor(.white.opacity(0.4))
                    HStack {
                        Slider(value: $layer.hOffset, in: 0.0...1.0).tint(.blue)
                        NumericField(value: $layer.hOffset).frame(width: 45).font(.caption2)
                    }
                    HStack {
                        Slider(value: $layer.vOffset, in: 0.0...1.0).tint(.blue)
                        NumericField(value: $layer.vOffset).frame(width: 45).font(.caption2)
                    }
                }

                HStack { Text(L10n.align(language)).font(.caption2).foregroundColor(.white.opacity(0.4)); Picker("", selection: $layer.hAlignment) { ForEach(ExifHAlignment.allCases) { Text($0.title(language)).tag($0) } }.pickerStyle(.segmented).labelsHidden() }

                Button(action: onRemove) { Text(L10n.removeLayer(language)).font(.caption).foregroundColor(.red) }.buttonStyle(.plain)
            }.padding(.top, 8)
        } label: {
            HStack {
                Button(action: { layer.isVisible.toggle() }) {
                    Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(layer.isVisible ? .blue : .white.opacity(0.3))
                        .font(.system(size: 11))
                }.buttonStyle(.plain)

                Text(layer.textTemplate.isEmpty ? L10n.emptyLayer(language) : layer.textTemplate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(layer.isVisible ? .white : .white.opacity(0.3))
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ClassicFontPicker: View {
    @Binding var selection: String
    let language: AppLanguage

    var body: some View {
        Picker(L10n.font(language), selection: $selection) {
            ForEach(FrameSettings.availableFonts, id: \.self) { fontName in
                Text(fontName)
                    .font(.custom(fontName, size: 12))
                    .tag(fontName)
            }
        }
    }
}

struct SearchableFontPicker: View {
    @Binding var selection: String
    let language: AppLanguage
    @State private var isPresented = false
    @State private var query = ""

    private var filteredFonts: [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return FrameSettings.availableFonts }

        let prefixMatches = FrameSettings.availableFonts.filter { $0.lowercased().hasPrefix(trimmedQuery) }
        let containsMatches = FrameSettings.availableFonts.filter {
            let name = $0.lowercased()
            return !name.hasPrefix(trimmedQuery) && name.contains(trimmedQuery)
        }
        return prefixMatches + containsMatches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.font(language)).font(.caption2).foregroundColor(.white.opacity(0.4))

            Button(action: {
                query = ""
                isPresented = true
            }) {
                HStack(spacing: 8) {
                    Text(selection)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(L10n.searchFonts(language), text: $query)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.preview(language)).font(.caption2).foregroundColor(.secondary)
                        Text(selection)
                            .font(.custom(selection, size: 14))
                            .lineLimit(1)
                    }

                    if filteredFonts.isEmpty {
                        Text(L10n.noFontsFound(language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredFonts, id: \.self) { fontName in
                                    Button(action: {
                                        selection = fontName
                                        isPresented = false
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: fontName == selection ? "checkmark" : "circle")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(fontName == selection ? .blue : .clear)
                                            Text(fontName)
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(fontName == selection ? Color.accentColor.opacity(0.12) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(width: 320, height: 360)
            }
        }
    }
}

// MARK: - Preset Menu

struct PresetMenu: View {
    @ObservedObject var settings: FrameSettings
    @Binding var presetsData: Data
    @Binding var showingAlert: Bool
    let language: AppLanguage
    let onRenamePreset: (Preset) -> Void
    
    var body: some View {
        Menu {
            let presets = (try? JSONDecoder().decode([Preset].self, from: presetsData)) ?? []
            if !presets.isEmpty {
                Text(L10n.savedPresets(language)).font(.caption)
                ForEach(presets) { preset in
                    Menu(preset.name) {
                        Button(L10n.applySelection(language)) { settings.apply(preset: preset) }
                        Button(L10n.renamePresetMenu(language)) { onRenamePreset(preset) }
                        Button(L10n.deletePreset(language), role: .destructive) { deletePreset(id: preset.id) }
                    }
                }
                Divider()
            }
            Button(action: { showingAlert = true }) { Label(L10n.saveCurrentAsPreset(language), systemImage: "plus") }
            if !presets.isEmpty {
                Button(role: .destructive, action: { presetsData = Data() }) { Label(L10n.clearAllPresets(language), systemImage: "trash") }
            }
        } label: {
            Image(systemName: "slider.horizontal.3")
                .foregroundColor(.white.opacity(0.8))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
    
    private func deletePreset(id: UUID) {
        var presets = (try? JSONDecoder().decode([Preset].self, from: presetsData)) ?? []
        presets.removeAll { $0.id == id }
        if let encoded = try? JSONEncoder().encode(presets) { presetsData = encoded }
    }
}

struct ExifChip: View {
    let name: String; let icon: String; @Binding var isOn: Bool
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 6) { Image(systemName: icon).font(.caption2); Text(name).font(.system(size: 11, weight: .medium)) }.frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(isOn ? Color.blue.opacity(0.2) : Color.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isOn ? Color.blue : Color.clear, lineWidth: 1))
        }.buttonStyle(.plain).foregroundColor(isOn ? .white : .white.opacity(0.5))
    }
}
