import AppKit
import AVFoundation
import CoreImage
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

        let videoRect = videoFrameRect(
            imageRect: layout.imageRect,
            renderSize: CGSize(width: layout.canvasWidth, height: layout.canvasHeight)
        )
        let renderSize = CGSize(
            width: layout.canvasWidth,
            height: layout.canvasHeight
        )
        let videoComposition = try makeExportVideoComposition(
            asset: composition,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            nominalFrameRate: nominalFrameRate,
            renderSize: renderSize,
            targetRect: videoRect,
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

    static func makePreviewVideoComposition(
        for url: URL,
        options: ImageProcessor.Options
    ) -> AVVideoComposition? {
        guard options.lutConfiguration != nil else { return nil }

        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }

        let naturalSize = track.naturalSize
        let preferredTransform = track.preferredTransform
        let orientedSize = orientedVideoSize(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform
        )

        let renderSize = CGSize(
            width: max(orientedSize.width.rounded(), 1),
            height: max(orientedSize.height.rounded(), 1)
        )
        let targetRect = CGRect(origin: .zero, size: renderSize)

        return makeVideoComposition(
            asset: asset,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            frameDuration: frameDuration(for: track.nominalFrameRate),
            renderSize: renderSize,
            targetRect: targetRect,
            overlayImage: nil,
            options: options
        )
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

    private static func makeExportVideoComposition(
        asset: AVAsset,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        nominalFrameRate: Float,
        renderSize: CGSize,
        targetRect: CGRect,
        layout: ImageProcessor.Layout,
        options: ImageProcessor.Options,
        exifInfo: ExifInfo
    ) throws -> AVVideoComposition {
        let overlayImage = try ImageProcessor.renderVideoOverlay(
            exifInfo: exifInfo,
            layout: layout,
            options: options
        )

        return makeVideoComposition(
            asset: asset,
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            frameDuration: frameDuration(for: nominalFrameRate),
            renderSize: renderSize,
            targetRect: targetRect,
            overlayImage: overlayImage,
            options: options
        )
    }

    private static func makeVideoComposition(
        asset: AVAsset,
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        frameDuration: CMTime,
        renderSize: CGSize,
        targetRect: CGRect,
        overlayImage: CGImage?,
        options: ImageProcessor.Options
    ) -> AVVideoComposition {
        let normalizedTransform = normalizedVideoTransform(
            preferredTransform: preferredTransform,
            naturalSize: naturalSize
        )
        let placementTransform = videoTransform(
            normalizedTransform: normalizedTransform,
            naturalSize: naturalSize,
            targetRect: targetRect
        )
        let overlayCIImage = overlayImage.map { CIImage(cgImage: $0) }
        let bounds = CGRect(origin: .zero, size: renderSize)

        let videoComposition = AVMutableVideoComposition(asset: asset) { request in
            let transformedVideo = request.sourceImage.transformed(by: placementTransform)
            let filteredVideo: CIImage

            do {
                filteredVideo = try ImageProcessor.applyLUT(to: transformedVideo, options: options)
            } catch {
                request.finish(with: error)
                return
            }

            let transparentCanvas = CIImage(color: .clear).cropped(to: bounds)
            var composedImage = filteredVideo.composited(over: transparentCanvas)

            if let overlayCIImage {
                composedImage = overlayCIImage.composited(over: composedImage)
            }

            request.finish(with: composedImage.cropped(to: bounds), context: nil)
        }

        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = frameDuration
        return videoComposition
    }

    private static func normalizedVideoTransform(
        preferredTransform: CGAffineTransform,
        naturalSize: CGSize
    ) -> CGAffineTransform {
        let sourceRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized

        return preferredTransform.concatenating(
            CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
        )
    }

    private static func videoTransform(
        normalizedTransform: CGAffineTransform,
        naturalSize: CGSize,
        targetRect: CGRect
    ) -> CGAffineTransform {
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
