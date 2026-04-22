import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Core image processing engine.
/// Reads a JPEG, extracts EXIF, draws the framed image with text overlay, and saves.
struct ImageProcessor {

    // MARK: - Public API

    struct TextLayerOptions: Sendable {
        let id: UUID
        let textTemplate: String
        let fontName: String
        let fontSizePercent: CGFloat
        let textColorComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        let hOffset: Double
        let vOffset: Double
        let hAlignment: ExifHAlignment
        let isVisible: Bool
    }

    struct Options: Sendable {
        let effectiveRatio: CGFloat?  // nil = original ratio
        let frameColorComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        let photoBorderEnabled: Bool
        let photoBorderColorComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        let photoBorderWidthPercent: CGFloat
        let paddingRatio: CGFloat
        
        let photoVOffset: Double
        let photoHOffset: Double
        let innerPadding: CGFloat
        
        let textLayers: [TextLayerOptions]
    }

    struct PreviewTextLayer: Identifiable {
        let id: UUID
        let text: String
        let fontName: String
        let fontSize: CGFloat
        let textColorComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        let origin: CGPoint
        let size: CGSize
    }

    private struct TextLayoutCacheKey: Hashable {
        let text: String
        let fontName: String
        let fontSizeBits: UInt64
        let redBits: UInt64
        let greenBits: UInt64
        let blueBits: UInt64
        let alphaBits: UInt64
        let alignment: ExifHAlignment
    }

    private struct TextLayoutCacheEntry {
        let attributedString: NSAttributedString
        let size: CGSize
    }

    private struct ResolvedTextLayout {
        let cachedLayout: TextLayoutCacheEntry
        let fontSize: CGFloat
        let origin: CGPoint
    }

    private final class TextLayoutCache: @unchecked Sendable {
        static let shared = TextLayoutCache()

        private let lock = NSLock()
        private var storage: [TextLayoutCacheKey: TextLayoutCacheEntry] = [:]
        private let maxEntries = 256

        func entry(
            text: String,
            fontName: String,
            fontSize: CGFloat,
            textColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
            alignment: ExifHAlignment
        ) -> TextLayoutCacheEntry {
            let key = TextLayoutCacheKey(
                text: text,
                fontName: fontName,
                fontSizeBits: Double(fontSize).bitPattern,
                redBits: Double(textColor.r).bitPattern,
                greenBits: Double(textColor.g).bitPattern,
                blueBits: Double(textColor.b).bitPattern,
                alphaBits: Double(textColor.a).bitPattern,
                alignment: alignment
            )

            lock.lock()
            if let cached = storage[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            let color = NSColor(
                red: textColor.r,
                green: textColor.g,
                blue: textColor.b,
                alpha: textColor.a
            )

            let paragraphStyle = NSMutableParagraphStyle()
            switch alignment {
            case .left: paragraphStyle.alignment = .left
            case .center: paragraphStyle.alignment = .center
            case .right: paragraphStyle.alignment = .right
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraphStyle,
            ]

            let attributedString = NSAttributedString(string: text, attributes: attributes)
            let entry = TextLayoutCacheEntry(
                attributedString: attributedString,
                size: attributedString.size()
            )

            lock.lock()
            if storage.count >= maxEntries {
                storage.removeAll(keepingCapacity: true)
            }
            storage[key] = entry
            lock.unlock()

            return entry
        }
    }

    /// Process a single image file and write the result to `outputURL`.
    static func process(
        inputURL: URL,
        outputURL: URL,
        options: Options,
        exportSettings: ExportSettings
    ) throws {
        // 1. Load image
        guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ProcessingError.cannotLoadImage
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]

        // 2. Extract EXIF
        let exifInfo = extractExif(from: imageSource)

        // 3. Determine orientation from EXIF and get oriented dimensions
        let orientation = extractOrientation(from: imageSource)
        let (orientedWidth, orientedHeight) = orientedDimensions(
            width: cgImage.width, height: cgImage.height, orientation: orientation
        )

        // 4. Calculate canvas and image rect
        let layout = calculateLayout(
            imageWidth: orientedWidth,
            imageHeight: orientedHeight,
            options: options
        )

        // 5. Render
        let rendered = try render(
            cgImage: cgImage,
            orientation: orientation,
            exifInfo: exifInfo,
            layout: layout,
            options: options
        )

        let finalImage = try resizedImageIfNeeded(
            image: rendered,
            maxLongEdge: exportSettings.maxLongEdge
        )
        let metadata = metadataProperties(
            from: sourceProperties,
            outputImage: finalImage,
            includeMetadata: exportSettings.copyMetadata
        )

        switch exportSettings.format {
        case .jpeg:
            try saveJPEG(
                image: finalImage,
                to: outputURL,
                quality: CGFloat(exportSettings.jpegQuality),
                properties: metadata
            )
        case .png:
            try savePNG(image: finalImage, to: outputURL, properties: metadata)
        }
    }

    // MARK: - EXIF Extraction

    static func extractExif(from source: CGImageSource) -> ExifInfo {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ExifInfo()
        }

        let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let gpsDict = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] ?? [:]
        let exifAuxDict = properties[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]

        var info = ExifInfo()
        info.metadataFields = flattenedMetadataFields(
            dictionaries: [exifDict, tiffDict, gpsDict, exifAuxDict]
        )

        info.cameraMake = tiffDict[kCGImagePropertyTIFFMake] as? String
        info.cameraModel = tiffDict[kCGImagePropertyTIFFModel] as? String

        if let lensModel = exifDict[kCGImagePropertyExifLensModel] as? String {
            info.lensModel = lensModel
        }

        if let fl = exifDict[kCGImagePropertyExifFocalLength] as? Double {
            info.focalLength = fl.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", fl)
                : String(format: "%.1f", fl)
        }

        if let fn = exifDict[kCGImagePropertyExifFNumber] as? Double {
            info.fNumber = fn.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0f", fn)
                : String(format: "%.1f", fn)
        }

        if let exposure = exifDict[kCGImagePropertyExifExposureTime] as? Double {
            if exposure >= 1 {
                info.exposureTime = String(format: "%.1fs", exposure)
            } else {
                let denominator = Int(round(1.0 / exposure))
                info.exposureTime = "1/\(denominator)s"
            }
        }

        if let isoArray = exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int],
           let iso = isoArray.first {
            info.iso = "\(iso)"
        }

        info.dateTaken = formattedCaptureDate(
            exifDateTimeOriginal: exifDict[kCGImagePropertyExifDateTimeOriginal] as? String,
            exifDateTimeDigitized: exifDict[kCGImagePropertyExifDateTimeDigitized] as? String,
            tiffDateTime: tiffDict[kCGImagePropertyTIFFDateTime] as? String
        )

        return info
    }

    private static func flattenedMetadataFields(
        dictionaries: [[CFString: Any]]
    ) -> [String: String] {
        var fields: [String: String] = [:]

        for dictionary in dictionaries {
            for (key, value) in dictionary {
                guard let stringValue = metadataString(from: value), !stringValue.isEmpty else { continue }
                fields[String(key)] = stringValue
            }
        }

        return fields
    }

    private static func metadataString(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }

        if let number = value as? NSNumber {
            return number.stringValue
        }

        if let values = value as? [Any] {
            let stringValues = values.compactMap { metadataString(from: $0) }
            return stringValues.isEmpty ? nil : stringValues.joined(separator: ", ")
        }

        if let dict = value as? [AnyHashable: Any] {
            let parts = dict.compactMap { key, nestedValue -> String? in
                guard let nestedString = metadataString(from: nestedValue) else { return nil }
                return "\(key)=\(nestedString)"
            }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }

        return String(describing: value)
    }

    private static func formattedCaptureDate(
        exifDateTimeOriginal: String?,
        exifDateTimeDigitized: String?,
        tiffDateTime: String?
    ) -> String? {
        let candidates = [exifDateTimeOriginal, exifDateTimeDigitized, tiffDateTime]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for candidate in candidates {
            if let parsed = parseEXIFDate(candidate) {
                return parsed
            }
        }

        return nil
    }

    private static func parseEXIFDate(_ value: String) -> String? {
        let formatters: [DateFormatter] = {
            let formats = [
                "yyyy:MM:dd HH:mm:ss",
                "yyyy:MM:dd HH:mm:ss.SSS",
                "yyyy:MM:dd HH:mm:ssXXXXX",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ssXXXXX"
            ]

            return formats.map { format in
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = format
                return formatter
            }
        }()

        let outputFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()

        for formatter in formatters {
            if let date = formatter.date(from: value) {
                return outputFormatter.string(from: date)
            }
        }

        let datePart = value.split(separator: " ").first.map(String.init) ?? value
        let normalized = datePart.replacingOccurrences(of: ":", with: "-")
        return normalized.isEmpty ? nil : normalized
    }

    // MARK: - Orientation

    static func extractOrientation(from source: CGImageSource) -> CGImagePropertyOrientation {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let orientationValue = properties[kCGImagePropertyOrientation] as? UInt32,
              let orientation = CGImagePropertyOrientation(rawValue: orientationValue) else {
            return .up
        }
        return orientation
    }

    /// Returns (width, height) after applying the EXIF orientation.
    static func orientedDimensions(
        width: Int, height: Int, orientation: CGImagePropertyOrientation
    ) -> (Int, Int) {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return (height, width)
        default:
            return (width, height)
        }
    }

    // MARK: - Layout Calculation

    struct Layout {
        let canvasWidth: Int
        let canvasHeight: Int
        let imageRect: CGRect // where the photo is drawn on the canvas
        let padding: CGFloat
        let textAreaHeight: CGFloat
    }

    static func calculateLayout(
        imageWidth: Int,
        imageHeight: Int,
        options: Options
    ) -> Layout {
        let imgW = CGFloat(imageWidth)
        let imgH = CGFloat(imageHeight)
        let largerDim = max(imgW, imgH)
        let padding = floor(largerDim * options.paddingRatio)
        let textAreaHeight = padding * 1.2
        let sideMargin = padding + textAreaHeight // Unified margin for all 4 sides

        let canvasW: CGFloat
        let canvasH: CGFloat

        if let targetRatio = options.effectiveRatio {
            // Apply unified margin to both dimensions
            let minCanvasW = imgW + sideMargin * 2
            let minCanvasH = imgH + sideMargin * 2

            if minCanvasW / minCanvasH > targetRatio {
                canvasW = minCanvasW
                canvasH = canvasW / targetRatio
            } else {
                canvasH = minCanvasH
                canvasW = canvasH * targetRatio
            }
        } else {
            canvasW = imgW + sideMargin * 2
            canvasH = imgH + sideMargin * 2
        }

        let availableH = canvasH - sideMargin * 2
        let availableW = canvasW - sideMargin * 2

        let scaleW = availableW / imgW
        let scaleH = availableH / imgH
        let scale = min(scaleW, scaleH, 1.0)

        let drawnW = imgW * scale
        let drawnH = imgH * scale

        // Symmetric centering within the sideMargin bounds
        let leewayX = canvasW - drawnW - sideMargin * 2
        let imageX = sideMargin + leewayX * options.photoHOffset
        
        let leewayY = canvasH - drawnH - sideMargin * 2
        let imageY = sideMargin + leewayY * (1.0 - options.photoVOffset)

        let imageRect = CGRect(x: imageX, y: imageY, width: drawnW, height: drawnH)
        
        return Layout(
            canvasWidth: Int(ceil(canvasW)),
            canvasHeight: Int(ceil(canvasH)),
            imageRect: imageRect,
            padding: padding,
            textAreaHeight: textAreaHeight
        )
    }

    static func scaledLayout(
        _ layout: Layout,
        maxLongEdge: Int?
    ) -> Layout {
        guard let maxLongEdge else { return layout }

        let currentLongEdge = max(layout.canvasWidth, layout.canvasHeight)
        guard currentLongEdge > maxLongEdge else { return layout }

        let scale = CGFloat(maxLongEdge) / CGFloat(currentLongEdge)
        return Layout(
            canvasWidth: max(Int((CGFloat(layout.canvasWidth) * scale).rounded()), 1),
            canvasHeight: max(Int((CGFloat(layout.canvasHeight) * scale).rounded()), 1),
            imageRect: CGRect(
                x: layout.imageRect.minX * scale,
                y: layout.imageRect.minY * scale,
                width: layout.imageRect.width * scale,
                height: layout.imageRect.height * scale
            ),
            padding: layout.padding * scale,
            textAreaHeight: layout.textAreaHeight * scale
        )
    }

    // MARK: - Rendering

    static func render(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        exifInfo: ExifInfo,
        layout: Layout,
        options: Options
    ) throws -> CGImage {
        let background = try renderBackground(cgImage: cgImage, orientation: orientation, layout: layout, options: options)
        return try renderTextLayers(backgroundImage: background, exifInfo: exifInfo, layout: layout, options: options)
    }

    static func renderBackground(
        cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        layout: Layout,
        options: Options
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.cannotCreateContext
        }

        let fc = options.frameColorComponents
        context.setFillColor(red: fc.r, green: fc.g, blue: fc.b, alpha: fc.a)
        context.fill(CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))

        context.saveGState()
        applyOrientationTransform(context: context, orientation: orientation, drawRect: layout.imageRect)
        context.draw(cgImage, in: layout.imageRect)
        context.restoreGState()

        if options.photoBorderEnabled {
            strokePhotoBorder(
                context: context,
                imageRect: layout.imageRect,
                color: options.photoBorderColorComponents,
                widthPercent: options.photoBorderWidthPercent
            )
        }

        guard let result = context.makeImage() else {
            throw ProcessingError.cannotRenderImage
        }
        return result
    }

    static func renderFrameBackground(
        layout: Layout,
        options: Options
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.cannotCreateContext
        }

        let fc = options.frameColorComponents
        context.setFillColor(red: fc.r, green: fc.g, blue: fc.b, alpha: fc.a)
        context.fill(CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))

        if options.photoBorderEnabled {
            strokePhotoBorder(
                context: context,
                imageRect: layout.imageRect,
                color: options.photoBorderColorComponents,
                widthPercent: options.photoBorderWidthPercent
            )
        }

        guard let result = context.makeImage() else {
            throw ProcessingError.cannotRenderImage
        }
        return result
    }

    static func renderTextLayers(
        backgroundImage: CGImage,
        exifInfo: ExifInfo,
        layout: Layout,
        options: Options
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.cannotCreateContext
        }

        // Draw cached background
        context.draw(backgroundImage, in: CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))

        for layer in options.textLayers {
            guard layer.isVisible else { continue }
            let text = exifInfo.format(template: layer.textTemplate)
            if !text.isEmpty {
                drawText(
                    context: context,
                    text: text,
                    layout: layout,
                    layerOptions: layer
                )
            }
        }

        guard let result = context.makeImage() else {
            throw ProcessingError.cannotRenderImage
        }
        return result
    }

    static func renderTextOverlay(
        exifInfo: ExifInfo,
        layout: Layout,
        options: Options
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.cannotCreateContext
        }

        context.clear(CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))

        for layer in options.textLayers {
            guard layer.isVisible else { continue }
            let text = exifInfo.format(template: layer.textTemplate)
            if !text.isEmpty {
                drawText(
                    context: context,
                    text: text,
                    layout: layout,
                    layerOptions: layer
                )
            }
        }

        guard let result = context.makeImage() else {
            throw ProcessingError.cannotRenderImage
        }
        return result
    }

    static func renderVideoOverlay(
        exifInfo: ExifInfo,
        layout: Layout,
        options: Options
    ) throws -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: layout.canvasWidth,
            height: layout.canvasHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.cannotCreateContext
        }

        context.clear(CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))

        let framePath = CGMutablePath()
        framePath.addRect(CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight))
        framePath.addRect(layout.imageRect)

        let fc = options.frameColorComponents
        context.saveGState()
        context.addPath(framePath)
        context.setFillColor(red: fc.r, green: fc.g, blue: fc.b, alpha: fc.a)
        context.drawPath(using: .eoFill)
        context.restoreGState()

        if options.photoBorderEnabled {
            strokePhotoBorder(
                context: context,
                imageRect: layout.imageRect,
                color: options.photoBorderColorComponents,
                widthPercent: options.photoBorderWidthPercent
            )
        }

        for layer in options.textLayers {
            guard layer.isVisible else { continue }
            let text = exifInfo.format(template: layer.textTemplate)
            if !text.isEmpty {
                drawText(
                    context: context,
                    text: text,
                    layout: layout,
                    layerOptions: layer
                )
            }
        }

        guard let result = context.makeImage() else {
            throw ProcessingError.cannotRenderImage
        }
        return result
    }

    static func previewTextLayers(
        exifInfo: ExifInfo,
        layout: Layout,
        options: Options
    ) -> [PreviewTextLayer] {
        options.textLayers.compactMap { layer in
            guard layer.isVisible else { return nil }
            let text = exifInfo.format(template: layer.textTemplate)
            guard !text.isEmpty else { return nil }

            let resolved = resolveTextLayout(
                text: text,
                layout: layout,
                layerOptions: layer
            )

            return PreviewTextLayer(
                id: layer.id,
                text: text,
                fontName: layer.fontName,
                fontSize: resolved.fontSize,
                textColorComponents: layer.textColorComponents,
                origin: resolved.origin,
                size: resolved.cachedLayout.size
            )
        }
    }

    static func applyOrientationTransform(context: CGContext, orientation: CGImagePropertyOrientation, drawRect: CGRect) {
        let cx = drawRect.midX
        let cy = drawRect.midY
        switch orientation {
        case .up: break
        case .upMirrored:
            context.translateBy(x: cx * 2, y: 0)
            context.scaleBy(x: -1, y: 1)
        case .down:
            context.translateBy(x: cx * 2, y: cy * 2)
            context.rotate(by: .pi)
        case .downMirrored:
            context.translateBy(x: 0, y: cy * 2)
            context.scaleBy(x: 1, y: -1)
        case .leftMirrored:
            context.translateBy(x: cx, y: cy)
            context.rotate(by: .pi / 2)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: -cx, y: -cy)
        case .right:
            context.translateBy(x: cx, y: cy)
            context.rotate(by: .pi / 2)
            context.translateBy(x: -cx, y: -cy)
        case .rightMirrored:
            context.translateBy(x: cx, y: cy)
            context.rotate(by: -.pi / 2)
            context.scaleBy(x: -1, y: 1)
            context.translateBy(x: -cx, y: -cy)
        case .left:
            context.translateBy(x: cx, y: cy)
            context.rotate(by: -.pi / 2)
            context.translateBy(x: -cx, y: -cy)
        }
    }

    static func drawText(
        context: CGContext,
        text: String,
        layout: Layout,
        layerOptions: TextLayerOptions
    ) {
        let resolved = resolveTextLayout(
            text: text,
            layout: layout,
            layerOptions: layerOptions
        )

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        resolved.cachedLayout.attributedString.draw(at: NSPoint(x: resolved.origin.x, y: resolved.origin.y))
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func resolveTextLayout(
        text: String,
        layout: Layout,
        layerOptions: TextLayerOptions
    ) -> ResolvedTextLayout {
        let canvasW = CGFloat(layout.canvasWidth)
        let canvasH = CGFloat(layout.canvasHeight)
        let dynamicFontSize = max(8, canvasH * (layerOptions.fontSizePercent / 100.0))
        let tc = layerOptions.textColorComponents
        let cachedLayout = TextLayoutCache.shared.entry(
            text: text,
            fontName: layerOptions.fontName,
            fontSize: dynamicFontSize,
            textColor: tc,
            alignment: layerOptions.hAlignment
        )
        let textSize = cachedLayout.size

        let rectWidth = canvasW - layout.padding * 2
        let rectOriginX = layout.padding

        let textXBase: CGFloat
        switch layerOptions.hAlignment {
        case .left: textXBase = rectOriginX
        case .center: textXBase = rectOriginX + (rectWidth - textSize.width) / 2.0
        case .right: textXBase = rectOriginX + rectWidth - textSize.width
        }

        let maxShift = (rectWidth - textSize.width) / 2.0
        let shift = (CGFloat(layerOptions.hOffset) - 0.5) * 2.0 * maxShift
        let textX = textXBase + shift

        let minTextY = layout.padding * 0.5
        let maxTextY = canvasH - layout.padding * 0.5 - textSize.height
        let textY = maxTextY - (maxTextY - minTextY) * layerOptions.vOffset

        return ResolvedTextLayout(
            cachedLayout: cachedLayout,
            fontSize: dynamicFontSize,
            origin: CGPoint(x: textX, y: textY)
        )
    }

    static func photoBorderMetrics(
        for imageRect: CGRect,
        widthPercent: CGFloat
    ) -> (rect: CGRect, lineWidth: CGFloat)? {
        let borderWidth = photoBorderWidth(for: imageRect, widthPercent: widthPercent)
        let inset = borderWidth / 2.0
        let strokeRect = imageRect.insetBy(dx: -inset, dy: -inset)

        guard strokeRect.width > 0, strokeRect.height > 0 else { return nil }
        return (strokeRect, borderWidth)
    }

    private static func strokePhotoBorder(
        context: CGContext,
        imageRect: CGRect,
        color: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        widthPercent: CGFloat
    ) {
        guard let borderMetrics = photoBorderMetrics(
            for: imageRect,
            widthPercent: widthPercent
        ) else { return }

        context.saveGState()
        context.setStrokeColor(red: color.r, green: color.g, blue: color.b, alpha: color.a)
        context.setLineWidth(borderMetrics.lineWidth)
        context.stroke(borderMetrics.rect)
        context.restoreGState()
    }

    private static func photoBorderWidth(for imageRect: CGRect, widthPercent: CGFloat) -> CGFloat {
        let resolvedPercent = max(widthPercent, 0.01) / 100.0
        return max(1, round(min(imageRect.width, imageRect.height) * resolvedPercent))
    }

    static func saveJPEG(
        image: CGImage,
        to url: URL,
        quality: CGFloat,
        properties: [CFString: Any]? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ProcessingError.cannotCreateOutput
        }
        var options = properties ?? [:]
        options[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        if !CGImageDestinationFinalize(destination) { throw ProcessingError.cannotWriteOutput }
    }

    static func savePNG(image: CGImage, to url: URL, properties: [CFString: Any]? = nil) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ProcessingError.cannotCreateOutput
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary?)
        if !CGImageDestinationFinalize(destination) { throw ProcessingError.cannotWriteOutput }
    }

    static func metadataProperties(
        from sourceProperties: [CFString: Any]?,
        outputImage: CGImage,
        includeMetadata: Bool
    ) -> [CFString: Any]? {
        guard includeMetadata, let sourceProperties else { return nil }

        var metadata: [CFString: Any] = [:]

        if let tiff = sourceProperties[kCGImagePropertyTIFFDictionary] {
            metadata[kCGImagePropertyTIFFDictionary] = tiff
        }
        if let gps = sourceProperties[kCGImagePropertyGPSDictionary] {
            metadata[kCGImagePropertyGPSDictionary] = gps
        }
        if let iptc = sourceProperties[kCGImagePropertyIPTCDictionary] {
            metadata[kCGImagePropertyIPTCDictionary] = iptc
        }
        if let exif = sourceProperties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            var updatedExif = exif
            updatedExif[kCGImagePropertyExifPixelXDimension] = outputImage.width
            updatedExif[kCGImagePropertyExifPixelYDimension] = outputImage.height
            metadata[kCGImagePropertyExifDictionary] = updatedExif
        }
        if let dpiWidth = sourceProperties[kCGImagePropertyDPIWidth] {
            metadata[kCGImagePropertyDPIWidth] = dpiWidth
        }
        if let dpiHeight = sourceProperties[kCGImagePropertyDPIHeight] {
            metadata[kCGImagePropertyDPIHeight] = dpiHeight
        }

        metadata[kCGImagePropertyOrientation] = 1
        metadata[kCGImagePropertyPixelWidth] = outputImage.width
        metadata[kCGImagePropertyPixelHeight] = outputImage.height

        return metadata
    }

    static func resizedImageIfNeeded(image: CGImage, maxLongEdge: Int?) throws -> CGImage {
        guard let maxLongEdge else { return image }

        let currentLongEdge = max(image.width, image.height)
        guard currentLongEdge > maxLongEdge else { return image }

        let scale = CGFloat(maxLongEdge) / CGFloat(currentLongEdge)
        let newWidth = max(Int((CGFloat(image.width) * scale).rounded()), 1)
        let newHeight = max(Int((CGFloat(image.height) * scale).rounded()), 1)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ProcessingError.cannotCreateContext
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))

        guard let scaledImage = context.makeImage() else {
            throw ProcessingError.cannotRenderImage
        }

        return scaledImage
    }

    static func generateThumbnail(for url: URL, maxSize: CGFloat = 200) -> NSImage? {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
}

enum ProcessingError: LocalizedError {
    case cannotLoadImage, cannotCreateContext, cannotRenderImage, cannotCreateOutput, cannotWriteOutput
    var errorDescription: String? {
        switch self {
        case .cannotLoadImage: return "Cannot load the image file."
        case .cannotCreateContext: return "Cannot create the rendering context."
        case .cannotRenderImage: return "Failed to render the final image."
        case .cannotCreateOutput: return "Cannot create the output file."
        case .cannotWriteOutput: return "Failed to write the output JPEG."
        }
    }
}
