import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Core image processing engine.
/// Reads a JPEG, extracts EXIF, draws the framed image with text overlay, and saves.
struct ImageProcessor {

    // MARK: - Public API

    struct Options: Sendable {
        let effectiveRatio: CGFloat?  // nil = original ratio
        let frameColorComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        let fontName: String
        let fontSizePercent: CGFloat  // percentage of canvas height
        let textColorComponents: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
        let showExif: Bool
        let exifFields: ExifFieldSelection
        let paddingRatio: CGFloat
        
        let photoVOffset: Double
        let exifVOffset: Double
        let exifHAlignment: ExifHAlignment
        let innerPadding: CGFloat
    }

    /// Process a single image file and write the result to `outputURL`.
    static func process(
        inputURL: URL,
        outputURL: URL,
        options: Options
    ) throws {
        // 1. Load image
        guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ProcessingError.cannotLoadImage
        }

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

        // 6. Save as JPEG
        try saveJPEG(image: rendered, to: outputURL, quality: 0.95)
    }

    // MARK: - EXIF Extraction

    static func extractExif(from source: CGImageSource) -> ExifInfo {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return ExifInfo()
        }

        let exifDict = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiffDict = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        var info = ExifInfo()

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

        return info
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
        let textRect: CGRect  // where the EXIF text goes
        let padding: CGFloat
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

        let canvasW: CGFloat
        let canvasH: CGFloat

        if let targetRatio = options.effectiveRatio {
            let minCanvasW = imgW + padding * 2
            let minCanvasH = imgH + padding * 3

            if minCanvasW / minCanvasH > targetRatio {
                canvasW = minCanvasW
                canvasH = canvasW / targetRatio
            } else {
                canvasH = minCanvasH
                canvasW = canvasH * targetRatio
            }
        } else {
            canvasW = imgW + padding * 2
            canvasH = imgH + padding * 3
        }

        let textAreaHeight = padding * 1.2 // slightly more room for alignment
        let availableH = canvasH - padding * 2 - textAreaHeight
        let availableW = canvasW - padding * 2

        let scaleW = availableW / imgW
        let scaleH = availableH / imgH
        let scale = min(scaleW, scaleH, 1.0)

        let drawnW = imgW * scale
        let drawnH = imgH * scale

        let imageX = (canvasW - drawnW) / 2.0
        
        // Linear interpolation for photo Y
        // 0.0 = Top, 1.0 = Bottom
        let minY = padding + textAreaHeight
        let maxY = canvasH - padding - drawnH
        let imageY = maxY - (maxY - minY) * options.photoVOffset

        // Linear interpolation for EXIF Y
        // 0.0 = Top, 1.0 = Bottom
        let minTextY = padding * 0.5
        let maxTextY = canvasH - padding * 0.5 - textAreaHeight
        let textAreaY = maxTextY - (maxTextY - minTextY) * options.exifVOffset

        let imageRect = CGRect(x: imageX, y: imageY, width: drawnW, height: drawnH)
        let textRect = CGRect(
            x: padding,
            y: textAreaY,
            width: canvasW - padding * 2,
            height: textAreaHeight
        )

        return Layout(
            canvasWidth: Int(ceil(canvasW)),
            canvasHeight: Int(ceil(canvasH)),
            imageRect: imageRect,
            textRect: textRect,
            padding: padding
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

        if options.showExif {
            let text = exifInfo.summaryLine(fields: options.exifFields)
            if !text.isEmpty {
                drawText(
                    context: context,
                    text: text,
                    in: layout.textRect,
                    fontName: options.fontName,
                    fontSizePercent: options.fontSizePercent,
                    textColor: options.textColorComponents,
                    canvasHeight: layout.canvasHeight,
                    hAlignment: options.exifHAlignment
                )
            }
        }

        guard let result = context.makeImage() else {
            throw ProcessingError.cannotRenderImage
        }
        return result
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
        in rect: CGRect,
        fontName: String,
        fontSizePercent: CGFloat,
        textColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        canvasHeight: Int,
        hAlignment: ExifHAlignment
    ) {
        let dynamicFontSize = max(8, CGFloat(canvasHeight) * (fontSizePercent / 100.0))
        let font = NSFont(name: fontName, size: dynamicFontSize) ?? NSFont.systemFont(ofSize: dynamicFontSize)
        let color = NSColor(red: textColor.r, green: textColor.g, blue: textColor.b, alpha: textColor.a)

        let paragraphStyle = NSMutableParagraphStyle()
        switch hAlignment {
        case .left: paragraphStyle.alignment = .left
        case .center: paragraphStyle.alignment = .center
        case .right: paragraphStyle.alignment = .right
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle,
        ]

        let attrString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attrString.size()

        let textX: CGFloat
        switch hAlignment {
        case .left: textX = rect.origin.x
        case .center: textX = rect.origin.x + (rect.width - textSize.width) / 2.0
        case .right: textX = rect.origin.x + rect.width - textSize.width
        }
        
        let textY = rect.origin.y + (rect.height - textSize.height) / 2.0

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        attrString.draw(at: NSPoint(x: textX, y: textY))
        NSGraphicsContext.restoreGraphicsState()
    }

    static func saveJPEG(image: CGImage, to url: URL, quality: CGFloat) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw ProcessingError.cannotCreateOutput
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        if !CGImageDestinationFinalize(destination) { throw ProcessingError.cannotWriteOutput }
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
