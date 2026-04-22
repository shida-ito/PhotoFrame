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

struct BackgroundOptions: Equatable, Sendable {
    let frameColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
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
        case .processing: return language == .japanese ? "処理中…" : "Processing…"
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
    var paddingRatio: CGFloat = 0.05
    var photoVOffset: Double = 0.5
    var photoHOffset: Double = 0.5
    var innerPadding: CGFloat = 0.3
    var textLayers: [TextLayer] = [.defaultExif]

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

struct ExifInfo: Sendable {
    var cameraMake: String?
    var cameraModel: String?
    var lensModel: String?
    var focalLength: String?
    var fNumber: String?
    var exposureTime: String?
    var iso: String?
    var dateTaken: String?

    func format(template: String) -> String {
        var str = template
        str = str.replacingOccurrences(of: "{Camera}", with: cameraModel ?? cameraMake ?? "")
        str = str.replacingOccurrences(of: "{Lens}", with: lensModel ?? "")
        str = str.replacingOccurrences(of: "{Focal}", with: focalLength ?? "")
        str = str.replacingOccurrences(of: "{FStop}", with: fNumber ?? "")
        str = str.replacingOccurrences(of: "{Shutter}", with: exposureTime ?? "")
        str = str.replacingOccurrences(of: "{ISO}", with: iso ?? "")
        str = str.replacingOccurrences(of: "{Date}", with: dateTaken ?? "")
        
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct PreviewBackgroundSignature: Equatable {
    let aspectRatio: AspectRatio
    let customWidth: String
    let customHeight: String
    let frameColor: CodableColor
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
