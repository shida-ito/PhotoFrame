import AppKit
import AVFoundation
import CoreGraphics

struct VideoProcessor {

    struct PreviewData {
        let posterImage: CGImage
        let exifInfo: ExifInfo
        let orientedSize: (width: Int, height: Int)
        let durationSeconds: Double
    }

    static func generateThumbnail(for url: URL, maxSize: CGFloat = 200) async -> NSImage? {
        guard let previewData = try? await loadPreviewData(from: url, maxDim: maxSize) else {
            return nil
        }

        return NSImage(
            cgImage: previewData.posterImage,
            size: NSSize(
                width: previewData.posterImage.width,
                height: previewData.posterImage.height
            )
        )
    }

    static func loadPreviewData(from url: URL, maxDim: CGFloat = 800) async throws -> PreviewData {
        let asset = AVURLAsset(url: url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        guard let videoTrack = videoTracks.first else {
            throw VideoProcessingError.cannotLoadVideo
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let orientedSize = orientedVideoSize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDim, height: maxDim)

        let previewTime = previewFrameTime(duration: duration)
        let posterImage = try generator.copyCGImage(at: previewTime, actualTime: nil)
        let exifInfo = await metadataInfo(
            asset: asset,
            url: url,
            durationSeconds: duration.seconds.isFinite ? duration.seconds : 0
        )

        return PreviewData(
            posterImage: posterImage,
            exifInfo: exifInfo,
            orientedSize: (
                width: max(Int(orientedSize.width.rounded()), 1),
                height: max(Int(orientedSize.height.rounded()), 1)
            ),
            durationSeconds: duration.seconds.isFinite ? duration.seconds : 0
        )
    }

    static func process(
        inputURL: URL,
        outputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        guard let sourceVideoTrack = videoTracks.first else {
            throw VideoProcessingError.cannotLoadVideo
        }

        let duration = try await asset.load(.duration)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let nominalFrameRate = try await sourceVideoTrack.load(.nominalFrameRate)

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoProcessingError.cannotCreateComposition
        }

        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideoTrack,
            at: .zero
        )

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for audioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }

            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }

        let orientedSize = orientedVideoSize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )
        let baseLayout = ImageProcessor.calculateLayout(
            imageWidth: max(Int(orientedSize.width.rounded()), 1),
            imageHeight: max(Int(orientedSize.height.rounded()), 1),
            options: options
        )
        let layout = ImageProcessor.scaledLayout(
            baseLayout,
            maxLongEdge: exportSettings.maxLongEdge
        )
        let exifInfo = await metadataInfo(
            asset: asset,
            url: inputURL,
            durationSeconds: duration.seconds.isFinite ? duration.seconds : 0
        )
        let commonMetadata = exportSettings.copyMetadata
            ? ((try? await asset.load(.commonMetadata)) ?? [])
            : []

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        let videoRect = videoFrameRect(
            imageRect: layout.imageRect,
            renderSize: CGSize(width: layout.canvasWidth, height: layout.canvasHeight)
        )
        let transform = videoTransform(
            preferredTransform: preferredTransform,
            naturalSize: naturalSize,
            targetRect: videoRect
        )
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]

        let videoComposition = AVMutableVideoComposition()
        videoComposition.instructions = [instruction]
        videoComposition.renderSize = CGSize(
            width: layout.canvasWidth,
            height: layout.canvasHeight
        )
        videoComposition.frameDuration = frameDuration(for: nominalFrameRate)
        videoComposition.animationTool = try animationTool(
            renderSize: videoComposition.renderSize,
            layout: layout,
            options: options,
            exifInfo: exifInfo
        )

        try? FileManager.default.removeItem(at: outputURL)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoProcessingError.cannotCreateExportSession
        }

        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition

        if exportSettings.copyMetadata {
            exportSession.metadata = commonMetadata
        }

        try await exportSession.export(to: outputURL, as: .mov)
    }

    private static func orientedVideoSize(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform
    ) -> CGSize {
        let transformedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized

        return CGSize(
            width: abs(transformedRect.width),
            height: abs(transformedRect.height)
        )
    }

    private static func previewFrameTime(duration: CMTime) -> CMTime {
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return .zero }
        return CMTime(seconds: min(seconds * 0.1, 0.5), preferredTimescale: 600)
    }

    private static func frameDuration(for nominalFrameRate: Float) -> CMTime {
        guard nominalFrameRate.isFinite, nominalFrameRate > 0 else {
            return CMTime(value: 1, timescale: 30)
        }

        return CMTime(value: 1, timescale: Int32(max(nominalFrameRate.rounded(), 1)))
    }

    private static func animationTool(
        renderSize: CGSize,
        layout: ImageProcessor.Layout,
        options: ImageProcessor.Options,
        exifInfo: ExifInfo
    ) throws -> AVVideoCompositionCoreAnimationTool {
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.masksToBounds = true

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)

        let overlayLayer = CALayer()
        overlayLayer.frame = parentLayer.bounds
        overlayLayer.contents = try ImageProcessor.renderVideoOverlay(
            exifInfo: exifInfo,
            layout: layout,
            options: options
        )
        overlayLayer.contentsGravity = .resize
        parentLayer.addSublayer(overlayLayer)

        return AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
    }

    private static func videoTransform(
        preferredTransform: CGAffineTransform,
        naturalSize: CGSize,
        targetRect: CGRect
    ) -> CGAffineTransform {
        let sourceRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let normalizedTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
        )

        let normalizedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(normalizedTransform)
            .standardized
        let scaleX = targetRect.width / max(normalizedRect.width, 1)
        let scaleY = targetRect.height / max(normalizedRect.height, 1)

        let scaledTransform = normalizedTransform.concatenating(
            CGAffineTransform(scaleX: scaleX, y: scaleY)
        )
        let scaledRect = CGRect(origin: .zero, size: naturalSize)
            .applying(scaledTransform)
            .standardized

        return scaledTransform.concatenating(
            CGAffineTransform(
                translationX: targetRect.minX - scaledRect.minX,
                y: targetRect.minY - scaledRect.minY
            )
        )
    }

    private static func videoFrameRect(
        imageRect: CGRect,
        renderSize: CGSize
    ) -> CGRect {
        CGRect(
            x: imageRect.minX,
            y: renderSize.height - imageRect.maxY,
            width: imageRect.width,
            height: imageRect.height
        )
    }

    private static func metadataInfo(
        asset: AVAsset,
        url: URL,
        durationSeconds: Double
    ) async -> ExifInfo {
        var info = ExifInfo()
        info.metadataFields["Filename"] = url.deletingPathExtension().lastPathComponent

        if durationSeconds > 0 {
            info.metadataFields["Duration"] = formattedDuration(durationSeconds)
        }

        if let creationDate = fileCreationDate(for: url) {
            info.dateTaken = creationDate
            info.metadataFields["FileDate"] = creationDate
        }

        let commonMetadata = (try? await asset.load(.commonMetadata)) ?? []

        for item in commonMetadata {
            guard let key = item.commonKey?.rawValue,
                  let value = await metadataString(from: item) else {
                continue
            }

            info.metadataFields[key] = value

            if key == "model", info.cameraModel == nil {
                info.cameraModel = value
            }
        }

        return info
    }

    private static func metadataString(from item: AVMetadataItem) async -> String? {
        if let stringValue = (try? await item.load(.stringValue))?.trimmingCharacters(in: .whitespacesAndNewlines),
           !stringValue.isEmpty {
            return stringValue
        }

        if let numberValue = try? await item.load(.numberValue) {
            return numberValue.stringValue
        }

        if let dateValue = try? await item.load(.dateValue) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: dateValue)
        }

        return nil
    }

    private static func fileCreationDate(for url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        let date = (attributes[.creationDate] as? Date) ?? (attributes[.modificationDate] as? Date)
        guard let date else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func formattedDuration(_ duration: Double) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum VideoProcessingError: LocalizedError {
    case cannotLoadVideo
    case cannotCreateComposition
    case cannotCreateExportSession
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .cannotLoadVideo:
            return "Cannot load the video file."
        case .cannotCreateComposition:
            return "Cannot create the video composition."
        case .cannotCreateExportSession:
            return "Cannot create the export session."
        case .exportFailed:
            return "Failed to export the video."
        }
    }
}
