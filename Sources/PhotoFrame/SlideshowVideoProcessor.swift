@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO

struct SlideshowVideoProcessor {

    private struct RenderedFrame {
        let image: CGImage
    }

    private static let frameRate = 30
    private static let timeScale: CMTimeScale = 600

    static func process(
        items: [PhotoItem],
        outputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings
    ) async throws {
        guard !items.isEmpty else {
            throw SlideshowVideoProcessingError.noImagesToExport
        }

        let renderedFrames = try items.map {
            try renderFrame(
                inputURL: $0.url,
                options: options,
                exportSettings: exportSettings
            )
        }
        let renderSize = renderSize(for: renderedFrames)
        let tempVideoURL = temporaryFileURL(pathExtension: "mov")

        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: tempVideoURL)

        let totalDuration = try await writeVideo(
            frames: renderedFrames,
            renderSize: renderSize,
            outputURL: tempVideoURL,
            frameColor: options.frameColorComponents,
            secondsPerPhoto: max(exportSettings.secondsPerPhoto, 0.1)
        )

        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        if let audioURL = resolveAudioURL(from: exportSettings.audioBookmarkData) {
            try await mergeAudio(
                videoURL: tempVideoURL,
                audioURL: audioURL,
                outputURL: outputURL,
                duration: totalDuration,
                exportSettings: exportSettings
            )
        } else {
            try FileManager.default.moveItem(at: tempVideoURL, to: outputURL)
        }
    }

    static func processPreview(
        items: [PhotoItem],
        outputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: Double
    ) async throws {
        guard !items.isEmpty else {
            throw SlideshowVideoProcessingError.noImagesToExport
        }

        let renderedFrames = try items.map {
            try renderFrame(
                inputURL: $0.url,
                options: options,
                exportSettings: exportSettings,
                previewMaxDimension: CGFloat(previewMaxDimension)
            )
        }
        let renderSize = renderSize(for: renderedFrames)
        let tempVideoURL = temporaryFileURL(pathExtension: "mov")

        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.removeItem(at: tempVideoURL)

        let totalDuration = try await writeVideo(
            frames: renderedFrames,
            renderSize: renderSize,
            outputURL: tempVideoURL,
            frameColor: options.frameColorComponents,
            secondsPerPhoto: max(exportSettings.secondsPerPhoto, 0.1)
        )

        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        if let audioURL = resolveAudioURL(from: exportSettings.audioBookmarkData) {
            try await mergeAudio(
                videoURL: tempVideoURL,
                audioURL: audioURL,
                outputURL: outputURL,
                duration: totalDuration,
                exportSettings: exportSettings
            )
        } else {
            try FileManager.default.moveItem(at: tempVideoURL, to: outputURL)
        }
    }

    private static func renderFrame(
        inputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat? = nil
    ) throws -> RenderedFrame {
        let cgImage: CGImage
        let exifInfo: ExifInfo
        let orientation: CGImagePropertyOrientation
        let orientedSize: (Int, Int)

        if let previewMaxDimension,
           let previewData = PhotoItem.loadImagePreviewData(from: inputURL, maxDim: previewMaxDimension) {
            cgImage = previewData.0
            exifInfo = previewData.1
            orientation = previewData.2
            orientedSize = (previewData.3, previewData.4)
        } else {
            guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let loadedImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ProcessingError.cannotLoadImage
            }

            cgImage = loadedImage
            exifInfo = ImageProcessor.extractExif(from: imageSource)
            orientation = ImageProcessor.extractOrientation(from: imageSource)
            orientedSize = ImageProcessor.orientedDimensions(
                width: loadedImage.width,
                height: loadedImage.height,
                orientation: orientation
            )
        }
        let layout = ImageProcessor.calculateLayout(
            imageWidth: orientedSize.0,
            imageHeight: orientedSize.1,
            options: options
        )
        let renderedImage = try ImageProcessor.render(
            cgImage: cgImage,
            orientation: orientation,
            exifInfo: exifInfo,
            layout: layout,
            options: options
        )
        let resizedImage = try ImageProcessor.resizedImageIfNeeded(
            image: renderedImage,
            maxLongEdge: exportSettings.maxLongEdge
        )

        return RenderedFrame(image: resizedImage)
    }

    private static func renderSize(for frames: [RenderedFrame]) -> CGSize {
        CGSize(
            width: frames.map(\.image.width).max() ?? 1,
            height: frames.map(\.image.height).max() ?? 1
        )
    }

    private static func writeVideo(
        frames: [RenderedFrame],
        renderSize: CGSize,
        outputURL: URL,
        frameColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        secondsPerPhoto: Double
    ) async throws -> CMTime {
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            throw SlideshowVideoProcessingError.cannotCreateWriter
        }

        let width = max(Int(renderSize.width.rounded()), 1)
        let height = max(Int(renderSize.height.rounded()), 1)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        writerInput.expectsMediaDataInRealTime = false

        let sourceBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: sourceBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw SlideshowVideoProcessingError.cannotCreateWriter
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw SlideshowVideoProcessingError.cannotCreateWriter
        }
        writer.startSession(atSourceTime: .zero)

        let framesPerPhoto = max(Int((secondsPerPhoto * Double(frameRate)).rounded()), 1)
        var frameIndex: Int64 = 0

        for frame in frames {
            for _ in 0..<framesPerPhoto {
                while !writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 1_000_000)
                }

                guard let pixelBufferPool = adaptor.pixelBufferPool else {
                    throw SlideshowVideoProcessingError.cannotCreatePixelBuffer
                }
                let pixelBuffer = try makePixelBuffer(
                    from: frame.image,
                    renderSize: CGSize(width: width, height: height),
                    frameColor: frameColor,
                    pixelBufferPool: pixelBufferPool
                )
                let presentationTime = CMTime(value: frameIndex, timescale: Int32(frameRate))
                guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                    throw SlideshowVideoProcessingError.cannotWriteVideo
                }
                frameIndex += 1
            }
        }

        writerInput.markAsFinished()
        try await finishWriting(writer)
        guard writer.status == .completed else {
            throw writer.error ?? SlideshowVideoProcessingError.cannotWriteVideo
        }

        return CMTime(value: frameIndex * Int64(timeScale), timescale: Int32(frameRate) * timeScale)
    }

    private static func makePixelBuffer(
        from image: CGImage,
        renderSize: CGSize,
        frameColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat),
        pixelBufferPool: CVPixelBufferPool
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw SlideshowVideoProcessingError.cannotCreatePixelBuffer
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw ProcessingError.cannotCreateContext
        }

        context.setFillColor(red: frameColor.r, green: frameColor.g, blue: frameColor.b, alpha: frameColor.a)
        context.fill(CGRect(origin: .zero, size: renderSize))

        let imageSize = CGSize(width: image.width, height: image.height)
        let imageRect = aspectFitRect(for: imageSize, in: CGRect(origin: .zero, size: renderSize))
        context.draw(image, in: imageRect)

        return pixelBuffer
    }

    private static func aspectFitRect(for imageSize: CGSize, in bounds: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }

        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fittedSize = CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )

        return CGRect(
            x: bounds.minX + (bounds.width - fittedSize.width) * 0.5,
            y: bounds.minY + (bounds.height - fittedSize.height) * 0.5,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    private static func mergeAudio(
        videoURL: URL,
        audioURL: URL,
        outputURL: URL,
        duration: CMTime,
        exportSettings: ExportSettings
    ) async throws {
        let videoAsset = AVURLAsset(url: videoURL)
        let audioAsset = AVURLAsset(url: audioURL)

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw SlideshowVideoProcessingError.cannotLoadVideoTrack
        }
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw SlideshowVideoProcessingError.cannotLoadAudioTrack
        }

        let audioDuration = try await audioAsset.load(.duration)
        guard audioDuration.seconds.isFinite, audioDuration.seconds > 0 else {
            throw SlideshowVideoProcessingError.cannotLoadAudioTrack
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SlideshowVideoProcessingError.cannotCreateComposition
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )

        guard let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw SlideshowVideoProcessingError.cannotCreateComposition
        }

        var cursor = CMTime.zero
        while cursor < duration {
            let remaining = duration - cursor
            let segmentDuration = min(audioDuration, remaining)
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: segmentDuration),
                of: audioTrack,
                at: cursor
            )
            cursor = cursor + segmentDuration
        }

        let audioMix = AVMutableAudioMix()
        let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
        let totalSeconds = max(duration.seconds, 0)
        let fadeInDuration = exportSettings.fadeInEnabled
            ? min(max(exportSettings.fadeInDuration, 0), totalSeconds)
            : 0
        let fadeOutDuration = exportSettings.fadeOutEnabled
            ? min(max(exportSettings.fadeOutDuration, 0), max(totalSeconds - fadeInDuration, 0))
            : 0

        if fadeInDuration > 0 {
            let fadeInTime = CMTime(seconds: fadeInDuration, preferredTimescale: timeScale)
            parameters.setVolumeRamp(
                fromStartVolume: 0,
                toEndVolume: 1,
                timeRange: CMTimeRange(start: .zero, duration: fadeInTime)
            )
            parameters.setVolume(1, at: fadeInTime)
        } else {
            parameters.setVolume(1, at: .zero)
        }

        if fadeOutDuration > 0 {
            let fadeOutStartSeconds = max(totalSeconds - fadeOutDuration, 0)
            parameters.setVolumeRamp(
                fromStartVolume: 1,
                toEndVolume: 0,
                timeRange: CMTimeRange(
                    start: CMTime(seconds: fadeOutStartSeconds, preferredTimescale: timeScale),
                    duration: CMTime(seconds: fadeOutDuration, preferredTimescale: timeScale)
                )
            )
        }

        audioMix.inputParameters = [parameters]

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SlideshowVideoProcessingError.cannotCreateExportSession
        }

        exportSession.audioMix = audioMix
        try? FileManager.default.removeItem(at: outputURL)
        try await exportSession.export(to: outputURL, as: .mov)
    }

    private static func finishWriting(_ writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = writer.error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func resolveAudioURL(from bookmarkData: Data?) -> URL? {
        guard let bookmarkData, !bookmarkData.isEmpty else { return nil }

        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private static func temporaryFileURL(pathExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }
}

enum SlideshowVideoProcessingError: LocalizedError {
    case noImagesToExport
    case cannotCreateWriter
    case cannotCreatePixelBuffer
    case cannotWriteVideo
    case cannotCreateComposition
    case cannotCreateExportSession
    case cannotLoadVideoTrack
    case cannotLoadAudioTrack

    var errorDescription: String? {
        switch self {
        case .noImagesToExport:
            return "No images are available for slideshow export."
        case .cannotCreateWriter:
            return "Cannot create the slideshow video writer."
        case .cannotCreatePixelBuffer:
            return "Cannot create a video frame buffer."
        case .cannotWriteVideo:
            return "Failed to write the slideshow video."
        case .cannotCreateComposition:
            return "Cannot create the slideshow composition."
        case .cannotCreateExportSession:
            return "Cannot create the slideshow export session."
        case .cannotLoadVideoTrack:
            return "Cannot load the rendered slideshow video."
        case .cannotLoadAudioTrack:
            return "Cannot load the selected audio track."
        }
    }
}
