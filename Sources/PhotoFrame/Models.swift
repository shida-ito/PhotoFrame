import SwiftUI

// MARK: - Aspect Ratio

enum AspectRatio: String, CaseIterable, Identifiable, Sendable {
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

enum ExifHAlignment: String, CaseIterable, Identifiable, Sendable {
    case left = "Left"
    case center = "Center"
    case right = "Right"
    var id: String { rawValue }
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

    init(url: URL) {
        self.url = url
        self.filename = url.lastPathComponent
    }
}

enum ProcessingStatus: Sendable {
    case pending
    case processing
    case completed
    case failed(String)

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .processing: return "Processing…"
        case .completed: return "Done"
        case .failed(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - EXIF Field Selection

struct ExifFieldSelection: Sendable {
    var showCamera: Bool = true
    var showLens: Bool = true
    var showFocalLength: Bool = true
    var showFNumber: Bool = true
    var showExposureTime: Bool = true
    var showISO: Bool = true
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

    func summaryLine(fields: ExifFieldSelection) -> String {
        var parts: [String] = []

        if fields.showCamera, let model = cameraModel { parts.append(model) }
        if fields.showLens, let lens = lensModel { parts.append(lens) }
        if fields.showFocalLength, let fl = focalLength { parts.append("\(fl)mm") }
        if fields.showFNumber, let f = fNumber { parts.append("f/\(f)") }
        if fields.showExposureTime, let exposure = exposureTime { parts.append(exposure) }
        if fields.showISO, let iso = iso { parts.append("ISO \(iso)") }

        return parts.joined(separator: "  •  ")
    }

    var summaryLine: String {
        summaryLine(fields: ExifFieldSelection())
    }
}

// MARK: - Frame Settings

@MainActor
final class FrameSettings: ObservableObject {
    @Published var aspectRatio: AspectRatio = .square
    @Published var customWidth: String = "4"
    @Published var customHeight: String = "5"
    @Published var frameColor: Color = .white
    @Published var fontName: String = "Helvetica Neue"
    @Published var fontSizePercent: CGFloat = 1.8
    @Published var textColor: Color = .gray
    @Published var showExif: Bool = true
    @Published var exifFields: ExifFieldSelection = ExifFieldSelection()
    @Published var paddingRatio: CGFloat = 0.05
    
    // Positioning
    @Published var photoVOffset: Double = 0.5 // 0.0 = Top, 0.5 = Center, 1.0 = Bottom
    @Published var exifVOffset: Double = 0.9  // 0.0 = Top, 1.0 = Bottom
    @Published var exifHAlignment: ExifHAlignment = .center
    @Published var innerPadding: CGFloat = 0.3 // ratio relative to padding

    var customRatio: CGFloat? {
        guard let w = Double(customWidth), let h = Double(customHeight), w > 0, h > 0 else { return nil }
        return CGFloat(w / h)
    }

    var effectiveRatio: CGFloat? {
        if aspectRatio == .custom { return customRatio }
        return aspectRatio.numericRatio
    }

    static let availableFonts: [String] = {
        NSFontManager.shared.availableFontFamilies.sorted()
    }()
}
