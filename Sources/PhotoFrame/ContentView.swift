import SwiftUI
import UniformTypeIdentifiers

// MARK: - Content View

struct ContentView: View {
    @StateObject private var settings = FrameSettings()
    @State private var photoItems: [PhotoItem] = []
    @State private var isProcessing = false
    @State private var isDragTargeted = false
    @State private var selectedItems: Set<UUID> = []
    @State private var previewImage: NSImage?
    @State private var isGeneratingPreview = false
    @State private var previewGeneration: Int = 0 

    var body: some View {
        ZStack {
            backgroundGradient
            mainHStack
        }
        .onReceive(settings.objectWillChange) { _ in
            // objectWillChange fires before properties update.
            // We schedule preview regeneration after the current update cycle.
            DispatchQueue.main.async {
                regeneratePreview()
            }
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
                Button(action: clearPhotos) { Label("Clear", systemImage: "trash").font(.caption) }
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
                    Text("Drop JPEG files here").font(.system(size: 16, weight: .medium, design: .rounded)).foregroundColor(.white.opacity(0.7))
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
                Text("\(photoItems.count) photo(s)").font(.caption).foregroundColor(.white.opacity(0.5))
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
                    Text("Process Sel (\(selectedItems.count))").font(.system(size: 12, weight: .semibold))
                }.padding(.horizontal, 14).padding(.vertical, 7).background(Color.white.opacity(0.1)).foregroundColor(.white).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(isProcessing || selectedItems.isEmpty).opacity(isProcessing || selectedItems.isEmpty ? 0.5 : 1.0)

            Button(action: processAllPhotos) {
                HStack(spacing: 6) {
                    if isProcessing { ProgressView().controlSize(.small).tint(.white) }
                    else { Image(systemName: "wand.and.stars").font(.system(size: 12)) }
                    Text(isProcessing ? "Processing…" : "Process All").font(.system(size: 12, weight: .semibold))
                }.padding(.horizontal, 14).padding(.vertical, 7).background(LinearGradient(colors: [.purple, .blue], startPoint: .leading, endPoint: .trailing)).foregroundColor(.white).clipShape(Capsule())
            }.buttonStyle(.plain).disabled(isProcessing || photoItems.isEmpty).opacity(isProcessing ? 0.7 : 1.0)
        }
    }

    private func photoRow(_ item: PhotoItem) -> some View {
        let isSelected = selectedItems.contains(item.id)
        return Button(action: { selectItem(item) }) {
            HStack(spacing: 10) {
                Group {
                    if let thumb = item.thumbnail { Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill) }
                    else { Rectangle().fill(Color.white.opacity(0.05)).overlay(ProgressView().controlSize(.small)) }
                }.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.filename).font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.9)).lineLimit(1)
                    Text(item.status.label).font(.caption2).foregroundColor(statusColor(item.status))
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
                Text("Preview").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.white.opacity(0.8))
                Spacer()
                if let item = photoItems.first(where: { selectedItems.contains($0.id) }) { Text(item.filename).font(.caption).foregroundColor(.white.opacity(0.4)).lineLimit(1) }
                Button(action: { selectedItems.removeAll(); previewImage = nil }) { Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundColor(.white.opacity(0.3)) }.buttonStyle(.plain)
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider().background(Color.white.opacity(0.08))
            ZStack {
                Color(nsColor: NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1))
                if isGeneratingPreview { ProgressView().controlSize(.regular) }
                else if let preview = previewImage { Image(nsImage: preview).resizable().aspectRatio(contentMode: .fit).padding(20).shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 8).transition(.opacity.combined(with: .scale(scale: 0.98))) }
                else { Text("Select a photo to preview").font(.caption).foregroundColor(.white.opacity(0.3)) }
            }.animation(.easeInOut(duration: 0.25), value: previewImage != nil)
        }
    }

    // MARK: - Settings

    private var settingsPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Settings").font(.system(size: 16, weight: .bold, design: .rounded)).foregroundColor(.white)
                
                AspectRatioSettings(settings: settings)
                AlignmentSettings(settings: settings)
                FrameStyleSettings(settings: settings)
                ExifFieldsSettings(settings: settings)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Image(systemName: "square.dashed").font(.caption).foregroundColor(.blue.opacity(0.8)); Text("Frame Width").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
                    Slider(value: $settings.paddingRatio, in: 0.02...0.15, step: 0.01).tint(.blue)
                    Text("\(Int(settings.paddingRatio * 100))%").font(.caption2).foregroundColor(.white.opacity(0.4))
                }
            }.padding(20)
        }.background(Color.white.opacity(0.03))
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
        Task.detached { let thumb = ImageProcessor.generateThumbnail(for: url); await MainActor.run { item.thumbnail = thumb } }
        if selectedItems.isEmpty { selectItem(item) }
    }

    private func removePhoto(_ item: PhotoItem) { photoItems.removeAll { $0.id == item.id }; selectedItems.remove(item.id); if selectedItems.isEmpty { previewImage = nil } }
    private func clearPhotos() { photoItems.removeAll(); selectedItems.removeAll(); previewImage = nil }
    private func selectItem(_ item: PhotoItem) { 
        if selectedItems.contains(item.id) { selectedItems.remove(item.id) }
        else { selectedItems.insert(item.id) }
        regeneratePreview() 
    }

    private func regeneratePreview() {
        guard let item = photoItems.first(where: { selectedItems.contains($0.id) }) else { previewImage = nil; return }
        previewGeneration += 1; let currentGen = previewGeneration; isGeneratingPreview = true
        let options = buildOptions(); let inputURL = item.url
        Task.detached {
            guard let isrc = CGImageSourceCreateWithURL(inputURL as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(isrc, 0, nil) else { await MainActor.run { if previewGeneration == currentGen { isGeneratingPreview = false } }; return }
            let exif = ImageProcessor.extractExif(from: isrc); let orient = ImageProcessor.extractOrientation(from: isrc); let (ow, oh) = ImageProcessor.orientedDimensions(width: cg.width, height: cg.height, orientation: orient)
            let s = min(1200.0 / CGFloat(ow), 1200.0 / CGFloat(oh), 1.0); let lay = ImageProcessor.calculateLayout(imageWidth: Int(CGFloat(ow)*s), imageHeight: Int(CGFloat(oh)*s), options: options)
            do {
                let r = try ImageProcessor.render(cgImage: cg, orientation: orient, exifInfo: exif, layout: lay, options: options); let ns = NSImage(cgImage: r, size: NSSize(width: r.width, height: r.height))
                await MainActor.run { if previewGeneration == currentGen { previewImage = ns; isGeneratingPreview = false } }
            } catch { await MainActor.run { if previewGeneration == currentGen { isGeneratingPreview = false } } }
        }
    }

    private func processAllPhotos() {
        guard !isProcessing else { return }; let p = NSOpenPanel(); p.canChooseDirectories = true; p.canCreateDirectories = true
        guard p.runModal() == .OK, let out = p.url else { return }; isProcessing = true; let opt = buildOptions()
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
        isProcessing = true; let opt = buildOptions()
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
    private func buildOptions() -> ImageProcessor.Options {
        let fNS = NSColor(settings.frameColor); let tNS = NSColor(settings.textColor)
        let fc = fNS.usingColorSpace(.sRGB) ?? fNS; let tc = tNS.usingColorSpace(.sRGB) ?? tNS
        return ImageProcessor.Options(
            effectiveRatio: settings.effectiveRatio, frameColorComponents: (r: fc.redComponent, g: fc.greenComponent, b: fc.blueComponent, a: fc.alphaComponent),
            fontName: settings.fontName, fontSizePercent: settings.fontSizePercent, textColorComponents: (r: tc.redComponent, g: tc.greenComponent, b: tc.blueComponent, a: tc.alphaComponent),
            showExif: settings.showExif, exifFields: settings.exifFields, paddingRatio: settings.paddingRatio,
            photoVOffset: settings.photoVOffset, photoHOffset: settings.photoHOffset,
            exifVOffset: settings.exifVOffset, exifHOffset: settings.exifHOffset,
            exifHAlignment: settings.exifHAlignment, innerPadding: settings.innerPadding
        )
    }
}

// MARK: - Subviews

struct AspectRatioSettings: View {
    @ObservedObject var settings: FrameSettings
    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "aspectratio").font(.caption).foregroundColor(.blue.opacity(0.8)); Text("Aspect Ratio").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(AspectRatio.allCases) { ratio in
                    Button(action: { settings.aspectRatio = ratio }) {
                        Text(ratio.rawValue).font(.system(size: 12)).frame(maxWidth: .infinity).padding(.vertical, 6)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "hand.tap.fill").font(.caption).foregroundColor(.blue.opacity(0.8)); Text("Photo Position").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            VStack(alignment: .leading, spacing: 4) {
                Text("Vertical").font(.caption2).foregroundColor(.white.opacity(0.4))
                HStack(spacing: 12) {
                    Image(systemName: "arrow.up.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                    Slider(value: $settings.photoVOffset, in: 0.0...1.0).tint(.blue)
                    Image(systemName: "arrow.down.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Horizontal").font(.caption2).foregroundColor(.white.opacity(0.4))
                HStack(spacing: 12) {
                    Image(systemName: "arrow.left.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                    Slider(value: $settings.photoHOffset, in: 0.0...1.0).tint(.blue)
                    Image(systemName: "arrow.right.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }
}

struct FrameStyleSettings: View {
    @ObservedObject var settings: FrameSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "paintpalette").font(.caption).foregroundColor(.blue.opacity(0.8)); Text("Frame & Font").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            HStack { Label("Frame", systemImage: "square").font(.caption2).foregroundColor(.white.opacity(0.4)); Spacer(); ColorPicker("", selection: $settings.frameColor).labelsHidden() }
            HStack { Label("Text", systemImage: "textformat").font(.caption2).foregroundColor(.white.opacity(0.4)); Spacer(); ColorPicker("", selection: $settings.textColor).labelsHidden() }
            Picker("Font", selection: $settings.fontName) {
                ForEach(FrameSettings.availableFonts, id: \.self) { fontName in
                    Text(fontName)
                        .font(.custom(fontName, size: 13))
                        .tag(fontName)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Text Size").font(.caption2).foregroundColor(.white.opacity(0.4))
                Slider(value: $settings.fontSizePercent, in: 0.5...5.0, step: 0.1).tint(.blue)
            }
        }
    }
}

struct ExifFieldsSettings: View {
    @ObservedObject var settings: FrameSettings
    let columns = [GridItem(.flexible()), GridItem(.flexible())]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Image(systemName: "tag.fill").font(.caption).foregroundColor(.blue.opacity(0.8)); Text("EXIF Fields").font(.system(size: 11, weight: .bold)).foregroundColor(.white.opacity(0.5)).textCase(.uppercase) }
            Toggle("Show EXIF Overlay", isOn: $settings.showExif).font(.system(size: 13, weight: .medium))
            if settings.showExif {
                LazyVGrid(columns: columns, spacing: 8) {
                    ExifChip(name: "Camera", icon: "camera.fill", isOn: $settings.exifFields.showCamera)
                    ExifChip(name: "Lens", icon: "camera.aperture", isOn: $settings.exifFields.showLens)
                    ExifChip(name: "Focal", icon: "scope", isOn: $settings.exifFields.showFocalLength)
                    ExifChip(name: "F-Stop", icon: "f.cursive", isOn: $settings.exifFields.showFNumber)
                    ExifChip(name: "Shutter", icon: "timer", isOn: $settings.exifFields.showExposureTime)
                    ExifChip(name: "ISO", icon: "speedometer", isOn: $settings.exifFields.showISO)
                }
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Vertical Position").font(.caption2).foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                            Slider(value: $settings.exifVOffset, in: 0.0...1.0).tint(.blue)
                            Image(systemName: "arrow.down.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Horizontal Position").font(.caption2).foregroundColor(.white.opacity(0.4))
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.left.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                            Slider(value: $settings.exifHOffset, in: 0.0...1.0).tint(.blue)
                            Image(systemName: "arrow.right.to.line").font(.caption2).foregroundColor(.white.opacity(0.3))
                        }
                    }
                    HStack { Text("Text Align").font(.caption2).foregroundColor(.white.opacity(0.4)); Picker("", selection: $settings.exifHAlignment) { ForEach(ExifHAlignment.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented).labelsHidden() }
                }
            }
        }
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
