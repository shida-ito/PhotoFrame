import SwiftUI

// MARK: - Aspect Ratio

enum AspectRatio: String, CaseIterable, Identifiable, Sendable, Codable {
    case original = "Original"
    case square = "1:1"
    case ratio4x5 = "4:5"
    case ratio5x4 = "5:4"
    case ratio3x2 = "3:2"
    case ratio2x3 = "2:3"
    case ratio16x9 = "16:9"
    case ratio9x16 = "9:16"
    case custom = "Custom"

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .original:
            return language == .japanese ? "元の比率" : rawValue
        case .custom:
            return language == .japanese ? "カスタム" : rawValue
        default:
            return rawValue
        }
    }

    /// Returns the numeric ratio (width / height), or nil for "original"
    var numericRatio: CGFloat? {
        switch self {
        case .original: return nil
        case .square: return 1.0
        case .ratio4x5: return 4.0 / 5.0
        case .ratio5x4: return 5.0 / 4.0
        case .ratio3x2: return 3.0 / 2.0
        case .ratio2x3: return 2.0 / 3.0
        case .ratio16x9: return 16.0 / 9.0
        case .ratio9x16: return 9.0 / 16.0
        case .custom: return nil
        }
    }
}

enum ExifHAlignment: String, CaseIterable, Identifiable, Sendable, Codable {
    case left = "Left"
    case center = "Center"
    case right = "Right"
    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .left: return language == .japanese ? "左" : rawValue
        case .center: return language == .japanese ? "中央" : rawValue
        case .right: return language == .japanese ? "右" : rawValue
        }
    }
}

enum FontSelectionDisplayMode: String, CaseIterable, Identifiable, Sendable, Codable {
    case compact
    case classic

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .compact: return language == .japanese ? "検索" : "Search"
        case .classic: return language == .japanese ? "一覧" : "Full List"
        }
    }

    func description(_ language: AppLanguage) -> String {
        switch self {
        case .compact:
            return language == .japanese ? "検索付きポップオーバーです。テキスト編集中の動作が軽くなります。" : "Searchable popover. Faster while editing text."
        case .classic:
            return language == .japanese ? "インラインのフォント一覧を表示します。" : "Shows an inline font list."
        }
    }
}

enum ExportFormat: String, CaseIterable, Identifiable, Sendable, Codable {
    case jpeg
    case png

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        }
    }
}

enum ExportSizePreset: String, CaseIterable, Identifiable, Sendable, Codable {
    case original
    case longEdge2048
    case longEdge4096
    case custom

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .original:
            return language == .japanese ? "元サイズ" : "Original Size"
        case .longEdge2048:
            return language == .japanese ? "長辺 2048px" : "Long Edge 2048px"
        case .longEdge4096:
            return language == .japanese ? "長辺 4096px" : "Long Edge 4096px"
        case .custom:
            return language == .japanese ? "長辺カスタム" : "Long Edge Custom"
        }
    }
}

struct ExportSettings: Equatable, Sendable, Codable {
    var format: ExportFormat = .jpeg
    var jpegQuality: Double = 0.95
    var sizePreset: ExportSizePreset = .original
    var customLongEdge: Int = 3000
    var filenamePrefix: String = "framed_"
    var copyMetadata: Bool = true

    var maxLongEdge: Int? {
        switch sizePreset {
        case .original:
            return nil
        case .longEdge2048:
            return 2048
        case .longEdge4096:
            return 4096
        case .custom:
            return max(customLongEdge, 1)
        }
    }
}

struct BackgroundOptions: Equatable, Sendable {
    let frameColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    let photoBorderEnabled: Bool
    let photoBorderColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    let photoBorderWidthPercent: CGFloat
    let paddingRatio: CGFloat
    let photoVOffset: Double
    let photoHOffset: Double
    let effectiveRatio: CGFloat?
    let previewMaxDim: Double
    
    static func == (lhs: BackgroundOptions, rhs: BackgroundOptions) -> Bool {
        lhs.frameColor.r == rhs.frameColor.r &&
        lhs.frameColor.g == rhs.frameColor.g &&
        lhs.frameColor.b == rhs.frameColor.b &&
        lhs.frameColor.a == rhs.frameColor.a &&
        lhs.photoBorderEnabled == rhs.photoBorderEnabled &&
        lhs.photoBorderColor.r == rhs.photoBorderColor.r &&
        lhs.photoBorderColor.g == rhs.photoBorderColor.g &&
        lhs.photoBorderColor.b == rhs.photoBorderColor.b &&
        lhs.photoBorderColor.a == rhs.photoBorderColor.a &&
        lhs.photoBorderWidthPercent == rhs.photoBorderWidthPercent &&
        lhs.paddingRatio == rhs.paddingRatio &&
        lhs.photoVOffset == rhs.photoVOffset &&
        lhs.photoHOffset == rhs.photoHOffset &&
        lhs.effectiveRatio == rhs.effectiveRatio &&
        lhs.previewMaxDim == rhs.previewMaxDim
    }
}

// MARK: - Photo Item

@MainActor
final class PhotoItem: ObservableObject, Identifiable {
    let id = UUID()
    let url: URL
    let filename: String

    @Published var status: ProcessingStatus = .pending
    @Published var thumbnail: NSImage?
    @Published var resultURL: URL?
    
    // Cached preview data (loaded once, reused on every settings change)
    var cachedPreviewImage: CGImage?
    var cachedExifInfo: ExifInfo?
    var cachedOrientation: CGImagePropertyOrientation?
    var cachedOrientedSize: (width: Int, height: Int)?
    
    // Cached intermediate render (frame + photo, no text)
    var cachedBackground: CGImage?
    var cachedBackgroundOptions: BackgroundOptions?

    init(url: URL) {
        self.url = url
        self.filename = url.lastPathComponent
    }
    
    /// Load and cache a downscaled version of the image for fast preview rendering.
    /// Call this on a background thread, then set properties on main thread.
    nonisolated static func loadPreviewData(from url: URL, maxDim: CGFloat = 800) -> (CGImage, ExifInfo, CGImagePropertyOrientation, Int, Int)? {
        guard let isrc = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        
        let exif = ImageProcessor.extractExif(from: isrc)
        let orient = ImageProcessor.extractOrientation(from: isrc)
        
        // Load a downscaled thumbnail directly from ImageIO (much faster than full decode)
        let thumbOpts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxDim,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: false
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(isrc, 0, thumbOpts as CFDictionary) else { return nil }
        
        let (ow, oh) = ImageProcessor.orientedDimensions(width: cg.width, height: cg.height, orientation: orient)
        return (cg, exif, orient, ow, oh)
    }
}

enum ProcessingStatus: Sendable {
    case pending
    case processing
    case completed
    case failed(String)

    func label(_ language: AppLanguage) -> String {
        switch self {
        case .pending: return language == .japanese ? "待機中" : "Pending"
        case .processing: return language == .japanese ? "書き出し中…" : "Exporting…"
        case .completed: return language == .japanese ? "完了" : "Done"
        case .failed(let msg): return language == .japanese ? "エラー: \(msg)" : "Error: \(msg)"
        }
    }
}

struct PhotoGroup: Identifiable {
    var id = UUID()
    var name: String
    var isDefaultGroup = false
    var isExpanded = true
    var settingsState = FrameSettingsState()
    var photoItems: [PhotoItem] = []

    static func ungrouped() -> PhotoGroup {
        PhotoGroup(name: "", isDefaultGroup: true)
    }

    func displayName(_ language: AppLanguage) -> String {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return language == .japanese ? "未分類" : "Ungrouped"
        }
        return name
    }
}

// MARK: - Presets & Codable

struct CodableColor: Codable, Equatable, Sendable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        self.red = ns.redComponent
        self.green = ns.greenComponent
        self.blue = ns.blueComponent
        self.alpha = ns.alphaComponent
    }

    var color: Color {
        Color(nsColor: NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha))
    }
}

struct FrameConfiguration: Equatable, Codable, Sendable {
    var aspectRatio: AspectRatio = .square
    var customWidth: String = "4"
    var customHeight: String = "5"
    var frameColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    var photoBorderEnabled = false
    var photoBorderColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
    var photoBorderWidthPercent: CGFloat = 0.3
    var paddingRatio: CGFloat = 0.05
    var photoVOffset: Double = 0.5
    var photoHOffset: Double = 0.5
    var innerPadding: CGFloat = 0.3
    var textLayers: [TextLayer] = [.defaultExif]

    enum CodingKeys: String, CodingKey {
        case aspectRatio
        case customWidth
        case customHeight
        case frameColor
        case photoBorderEnabled
        case photoBorderColor
        case photoBorderWidthPercent
        case paddingRatio
        case photoVOffset
        case photoHOffset
        case innerPadding
        case textLayers
    }

    init(
        aspectRatio: AspectRatio = .square,
        customWidth: String = "4",
        customHeight: String = "5",
        frameColor: CodableColor = CodableColor(red: 1, green: 1, blue: 1, alpha: 1),
        photoBorderEnabled: Bool = false,
        photoBorderColor: CodableColor = CodableColor(red: 0, green: 0, blue: 0, alpha: 1),
        photoBorderWidthPercent: CGFloat = 0.3,
        paddingRatio: CGFloat = 0.05,
        photoVOffset: Double = 0.5,
        photoHOffset: Double = 0.5,
        innerPadding: CGFloat = 0.3,
        textLayers: [TextLayer] = [.defaultExif]
    ) {
        self.aspectRatio = aspectRatio
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.frameColor = frameColor
        self.photoBorderEnabled = photoBorderEnabled
        self.photoBorderColor = photoBorderColor
        self.photoBorderWidthPercent = photoBorderWidthPercent
        self.paddingRatio = paddingRatio
        self.photoVOffset = photoVOffset
        self.photoHOffset = photoHOffset
        self.innerPadding = innerPadding
        self.textLayers = textLayers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        aspectRatio = try container.decodeIfPresent(AspectRatio.self, forKey: .aspectRatio) ?? .square
        customWidth = try container.decodeIfPresent(String.self, forKey: .customWidth) ?? "4"
        customHeight = try container.decodeIfPresent(String.self, forKey: .customHeight) ?? "5"
        frameColor = try container.decodeIfPresent(CodableColor.self, forKey: .frameColor) ?? CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
        photoBorderEnabled = try container.decodeIfPresent(Bool.self, forKey: .photoBorderEnabled) ?? false
        photoBorderColor = try container.decodeIfPresent(CodableColor.self, forKey: .photoBorderColor) ?? CodableColor(red: 0, green: 0, blue: 0, alpha: 1)
        photoBorderWidthPercent = try container.decodeIfPresent(CGFloat.self, forKey: .photoBorderWidthPercent) ?? 0.3
        paddingRatio = try container.decodeIfPresent(CGFloat.self, forKey: .paddingRatio) ?? 0.05
        photoVOffset = try container.decodeIfPresent(Double.self, forKey: .photoVOffset) ?? 0.5
        photoHOffset = try container.decodeIfPresent(Double.self, forKey: .photoHOffset) ?? 0.5
        innerPadding = try container.decodeIfPresent(CGFloat.self, forKey: .innerPadding) ?? 0.3
        textLayers = try container.decodeIfPresent([TextLayer].self, forKey: .textLayers) ?? [.defaultExif]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(aspectRatio, forKey: .aspectRatio)
        try container.encode(customWidth, forKey: .customWidth)
        try container.encode(customHeight, forKey: .customHeight)
        try container.encode(frameColor, forKey: .frameColor)
        try container.encode(photoBorderEnabled, forKey: .photoBorderEnabled)
        try container.encode(photoBorderColor, forKey: .photoBorderColor)
        try container.encode(photoBorderWidthPercent, forKey: .photoBorderWidthPercent)
        try container.encode(paddingRatio, forKey: .paddingRatio)
        try container.encode(photoVOffset, forKey: .photoVOffset)
        try container.encode(photoHOffset, forKey: .photoHOffset)
        try container.encode(innerPadding, forKey: .innerPadding)
        try container.encode(textLayers, forKey: .textLayers)
    }

    var customRatio: CGFloat? {
        guard let w = Double(customWidth), let h = Double(customHeight), w > 0, h > 0 else { return nil }
        return CGFloat(w / h)
    }

    var effectiveRatio: CGFloat? {
        if aspectRatio == .custom { return customRatio }
        return aspectRatio.numericRatio
    }

    var backgroundPreviewSignature: PreviewBackgroundSignature {
        PreviewBackgroundSignature(
            aspectRatio: aspectRatio,
            customWidth: customWidth,
            customHeight: customHeight,
            frameColor: frameColor,
            photoBorderEnabled: photoBorderEnabled,
            photoBorderColor: photoBorderColor,
            photoBorderWidthPercent: photoBorderWidthPercent,
            paddingRatio: paddingRatio,
            photoVOffset: photoVOffset,
            photoHOffset: photoHOffset,
            innerPadding: innerPadding
        )
    }

    var colorValue: Color {
        get { frameColor.color }
        set { frameColor = CodableColor(color: newValue) }
    }

    var photoBorderColorValue: Color {
        get { photoBorderColor.color }
        set { photoBorderColor = CodableColor(color: newValue) }
    }
}

struct Preset: Identifiable, Codable, Equatable, Sendable {
    var id = UUID()
    var name: String
    var configuration: FrameConfiguration

    enum CodingKeys: String, CodingKey {
        case id, name
        case configuration

        // Removed orientation-based preset keys kept for backward compatibility
        case usesOrientationBasedSettings
        case defaultConfiguration, portraitConfiguration, landscapeConfiguration, squareConfiguration

        // Legacy flat preset keys
        case aspectRatio, customWidth, customHeight, frameColor, paddingRatio
        case photoVOffset, photoHOffset, innerPadding, textLayers
    }

    init(
        id: UUID = UUID(),
        name: String,
        configuration: FrameConfiguration
    ) {
        self.id = id
        self.name = name
        self.configuration = configuration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)

        if let configuration = try container.decodeIfPresent(FrameConfiguration.self, forKey: .configuration) {
            self.configuration = configuration
            return
        }

        if let defaultConfiguration = try container.decodeIfPresent(FrameConfiguration.self, forKey: .defaultConfiguration) {
            configuration = defaultConfiguration
            return
        }

        configuration = FrameConfiguration(
            aspectRatio: try container.decode(AspectRatio.self, forKey: .aspectRatio),
            customWidth: try container.decode(String.self, forKey: .customWidth),
            customHeight: try container.decode(String.self, forKey: .customHeight),
            frameColor: try container.decode(CodableColor.self, forKey: .frameColor),
            paddingRatio: try container.decode(CGFloat.self, forKey: .paddingRatio),
            photoVOffset: try container.decode(Double.self, forKey: .photoVOffset),
            photoHOffset: try container.decode(Double.self, forKey: .photoHOffset),
            innerPadding: try container.decode(CGFloat.self, forKey: .innerPadding),
            textLayers: try container.decode([TextLayer].self, forKey: .textLayers)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(configuration, forKey: .configuration)
    }
}

// MARK: - Text Layer

struct TextLayer: Identifiable, Equatable, Sendable, Codable {
    var id = UUID()
    var textTemplate: String
    var fontName: String
    var fontSizePercent: CGFloat
    var textColor: Color
    var hOffset: Double
    var vOffset: Double
    var hAlignment: ExifHAlignment
    var isVisible: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case id, textTemplate, fontName, fontSizePercent, textColor, hOffset, vOffset, hAlignment, isVisible
    }
    
    init(id: UUID = UUID(), textTemplate: String, fontName: String, fontSizePercent: CGFloat, textColor: Color, hOffset: Double, vOffset: Double, hAlignment: ExifHAlignment, isVisible: Bool = true) {
        self.id = id
        self.textTemplate = textTemplate
        self.fontName = fontName
        self.fontSizePercent = fontSizePercent
        self.textColor = textColor
        self.hOffset = hOffset
        self.vOffset = vOffset
        self.hAlignment = hAlignment
        self.isVisible = isVisible
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        textTemplate = try container.decode(String.self, forKey: .textTemplate)
        fontName = try container.decode(String.self, forKey: .fontName)
        fontSizePercent = try container.decode(CGFloat.self, forKey: .fontSizePercent)
        let cColor = try container.decode(CodableColor.self, forKey: .textColor)
        textColor = cColor.color
        hOffset = try container.decode(Double.self, forKey: .hOffset)
        vOffset = try container.decode(Double.self, forKey: .vOffset)
        hAlignment = try container.decode(ExifHAlignment.self, forKey: .hAlignment)
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(textTemplate, forKey: .textTemplate)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(fontSizePercent, forKey: .fontSizePercent)
        try container.encode(CodableColor(color: textColor), forKey: .textColor)
        try container.encode(hOffset, forKey: .hOffset)
        try container.encode(vOffset, forKey: .vOffset)
        try container.encode(hAlignment, forKey: .hAlignment)
        try container.encode(isVisible, forKey: .isVisible)
    }

    static let defaultExif = TextLayer(
        textTemplate: "{Camera} • {Lens} • {Focal}mm • f/{FStop} • {Shutter} • ISO {ISO}",
        fontName: "Helvetica Neue",
        fontSizePercent: 1.8,
        textColor: .gray,
        hOffset: 0.5,
        vOffset: 0.9,
        hAlignment: .center
    )
}

// MARK: - Exif Display Fields

struct ExifMetadataTag: Identifiable, Hashable, Sendable {
    let name: String
    let value: String

    var id: String { name }
}

struct ExifInfo: Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: String?
    var fNumber: String?
    var exposureTime: String?
    var iso: String?
    var dateTaken: String?
    var metadataFields: [String: String] = [:]

    private var dateComponents: (year: String, month: String, day: String)? {
        guard let dateTaken else { return nil }
        let components = dateTaken.split(separator: "-").map(String.init)
        guard components.count >= 3 else { return nil }
        return (year: components[0], month: components[1], day: components[2])
    }

    var availableMetadataTags: [ExifMetadataTag] {
        metadataFields
            .keys
            .sorted()
            .compactMap { key in
                guard let value = metadataFields[key], !value.isEmpty else { return nil }
                return ExifMetadataTag(name: key, value: value)
            }
    }

    private var templateValues: [String: String] {
        var values = metadataFields
        values["Camera"] = cameraModel ?? cameraMake ?? ""
        values["Lens"] = lensModel ?? ""
        values["Focal"] = focalLength ?? ""
        values["FStop"] = fNumber ?? ""
        values["Shutter"] = exposureTime ?? ""
        values["ISO"] = iso ?? ""
        values["Date"] = dateTaken ?? ""
        values["Year"] = dateComponents?.year ?? ""
        values["Month"] = dateComponents?.month ?? ""
        values["Day"] = dateComponents?.day ?? ""
        return values
    }

    func format(template: String) -> String {
        let values = templateValues
        guard let regex = try? NSRegularExpression(pattern: #"\{([^{}]+)\}"#) else {
            return template.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let nsTemplate = template as NSString
        let matches = regex.matches(
            in: template,
            range: NSRange(location: 0, length: nsTemplate.length)
        )

        let resolved = matches.reversed().reduce(template) { partialResult, match in
            guard match.numberOfRanges > 1 else { return partialResult }
            let key = nsTemplate.substring(with: match.range(at: 1))
            guard let replacement = values[key] else { return partialResult }

            let mutable = partialResult as NSString
            return mutable.replacingCharacters(in: match.range, with: replacement)
        }

        return resolved.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PreviewBackgroundSignature: Equatable {
    let aspectRatio: AspectRatio
    let customWidth: String
    let customHeight: String
    let frameColor: CodableColor
    let photoBorderEnabled: Bool
    let photoBorderColor: CodableColor
    let photoBorderWidthPercent: CGFloat
    let paddingRatio: CGFloat
    let photoVOffset: Double
    let photoHOffset: Double
    let innerPadding: CGFloat
}

struct FrameSettingsState: Equatable, Codable, Sendable {
    var configuration = FrameConfiguration()

    mutating func setEditorConfiguration(_ configuration: FrameConfiguration) {
        self.configuration = configuration
    }
}

struct PersistedPhotoGroup: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var isDefaultGroup: Bool
    var isExpanded: Bool
    var settingsState: FrameSettingsState
    var photoPaths: [String]
}

struct PersistedWorkspace: Codable, Sendable {
    var selectedGroupID: UUID?
    var groups: [PersistedPhotoGroup]
}

// MARK: - Frame Settings

@MainActor
final class FrameSettings: ObservableObject {
    @Published private var configuration = FrameConfiguration()

    static let availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()

    var state: FrameSettingsState {
        get {
            FrameSettingsState(configuration: configuration)
        }
        set {
            configuration = newValue.configuration
        }
    }

    var editorConfigurationBinding: Binding<FrameConfiguration> {
        Binding(
            get: { self.editorConfiguration },
            set: { self.setEditorConfiguration($0) }
        )
    }

    var editorConfiguration: FrameConfiguration {
        configuration
    }

    private func setEditorConfiguration(_ configuration: FrameConfiguration) {
        self.configuration = configuration
    }
    
    // MARK: - Preset Management
    
    func apply(preset: Preset) {
        configuration = preset.configuration
    }

    func createPreset(name: String) -> Preset {
        Preset(
            name: name,
            configuration: configuration
        )
    }

    func apply(state: FrameSettingsState) {
        self.state = state
    }
}
