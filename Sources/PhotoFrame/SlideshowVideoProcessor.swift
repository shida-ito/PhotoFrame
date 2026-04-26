@preconcurrency import AVFoundation
import CoreGraphics
import ImageIO

struct SlideshowVideoProcessor {

    private struct RenderedFrame {
        let image: CGImage
    }

    private struct SegmentClip {
        let url: URL
        let duration: CMTime
        let renderSize: CGSize
    }

    private static let frameRate = 30
    private static let timeScale: CMTimeScale = 600

    static func process(
        items: [PhotoItem],
        outputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings
    ) async throws {
        try await processInternal(
            items: items,
            outputURL: outputURL,
            options: options,
            exportSettings: exportSettings,
            previewMaxDimension: nil
        )
    }

    static func processPreview(
        items: [PhotoItem],
        outputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: Double
    ) async throws {
        try await processInternal(
            items: items,
            outputURL: outputURL,
            options: options,
            exportSettings: exportSettings,
            previewMaxDimension: CGFloat(previewMaxDimension)
        )
    }

    private static func processInternal(
        items: [PhotoItem],
        outputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?
    ) async throws {
        guard !items.isEmpty else {
            throw SlideshowVideoProcessingError.noItemsToExport
        }

        try? FileManager.default.removeItem(at: outputURL)
        let renderSize = try await commonRenderSize(
            for: items,
            options: options,
            exportSettings: exportSettings,
            previewMaxDimension: previewMaxDimension
        )
        let clips = try await buildSegmentClips(
            from: items,
            options: options,
            exportSettings: exportSettings,
            previewMaxDimension: previewMaxDimension,
            renderSize: renderSize
        )
        defer {
            for clip in clips {
                try? FileManager.default.removeItem(at: clip.url)
            }
        }

        try await stitchClips(
            clips,
            renderSize: renderSize,
            outputURL: outputURL,
            exportSettings: exportSettings
        )
    }

    private static func buildSegmentClips(
        from items: [PhotoItem],
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?,
        renderSize: CGSize
    ) async throws -> [SegmentClip] {
        var clips: [SegmentClip] = []
        clips.reserveCapacity(items.count)

        for item in items {
            let clip: SegmentClip
            if item.mediaKind.isVideo {
                clip = try await renderVideoClip(
                    inputURL: item.url,
                    options: options,
                    exportSettings: exportSettings,
                    renderSize: renderSize
                )
            } else {
                clip = try await renderImageClip(
                    inputURL: item.url,
                    options: options,
                    exportSettings: exportSettings,
                    previewMaxDimension: previewMaxDimension,
                    renderSize: renderSize
                )
            }
            clips.append(clip)
        }

        return clips
    }

    private static func commonRenderSize(
        for items: [PhotoItem],
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?
    ) async throws -> CGSize {
        let maxLongEdge = effectiveMaxLongEdge(
            exportSettings: exportSettings,
            previewMaxDimension: previewMaxDimension
        )
        let exactLongEdge = exactExportLongEdge(
            exportSettings: exportSettings,
            previewMaxDimension: previewMaxDimension
        )
        let shouldUseSmallestCanvas = exportSettings.maxLongEdge == nil

        guard options.effectiveRatio != nil else {
            var referenceSize: CGSize?

            for item in items {
                let itemSize = try await itemRenderSize(
                    item,
                    options: options,
                    exportSettings: exportSettings,
                    previewMaxDimension: previewMaxDimension
                )

                if shouldReplaceReferenceSize(
                    current: referenceSize,
                    candidate: itemSize,
                    useSmallest: shouldUseSmallestCanvas
                ) {
                    referenceSize = itemSize
                }
            }

            return scaledRenderSize(
                referenceSize ?? CGSize(width: 1, height: 1),
                exactLongEdge: exactLongEdge,
                maxLongEdge: maxLongEdge
            )
        }

        var referenceSize: CGSize?

        for item in items {
            let itemSize = try await itemRenderSize(
                item,
                options: options,
                exportSettings: exportSettings,
                previewMaxDimension: previewMaxDimension
            )

            if shouldReplaceReferenceSize(
                current: referenceSize,
                candidate: itemSize,
                useSmallest: shouldUseSmallestCanvas
            ) {
                referenceSize = itemSize
            }
        }

        let baseSize = referenceSize ?? CGSize(width: 1, height: 1)

        if let ratio = options.effectiveRatio, ratio > 0 {
            var width = baseSize.width
            var height = width / ratio

            if height < baseSize.height {
                height = baseSize.height
                width = height * ratio
            }

            return scaledRenderSize(
                CGSize(
                    width: max(width.rounded(.up), 1),
                    height: max(height.rounded(.up), 1)
                ),
                exactLongEdge: exactLongEdge,
                maxLongEdge: maxLongEdge
            )
        }

        return scaledRenderSize(
            baseSize,
            exactLongEdge: exactLongEdge,
            maxLongEdge: maxLongEdge
        )
    }

    private static func shouldReplaceReferenceSize(
        current: CGSize?,
        candidate: CGSize,
        useSmallest: Bool
    ) -> Bool {
        guard let current else { return true }

        let currentArea = max(current.width, 1) * max(current.height, 1)
        let candidateArea = max(candidate.width, 1) * max(candidate.height, 1)
        return useSmallest ? candidateArea < currentArea : candidateArea > currentArea
    }

    private static func itemRenderSize(
        _ item: PhotoItem,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?
    ) async throws -> CGSize {
        if item.mediaKind.isVideo {
            return try await videoRenderSize(
                inputURL: item.url,
                options: options,
                exportSettings: exportSettings,
                previewMaxDimension: previewMaxDimension
            )
        }

        return try imageRenderSize(
            inputURL: item.url,
            options: options,
            exportSettings: exportSettings,
            previewMaxDimension: previewMaxDimension
        )
    }

    private static func imageRenderSize(
        inputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?
    ) throws -> CGSize {
        let orientedSize: (Int, Int)

        if let previewMaxDimension,
           let previewData = PhotoItem.loadImagePreviewData(from: inputURL, maxDim: previewMaxDimension) {
            orientedSize = (previewData.3, previewData.4)
        } else {
            guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ProcessingError.cannotLoadImage
            }
            let orientation = ImageProcessor.extractOrientation(from: imageSource)
            orientedSize = ImageProcessor.orientedDimensions(
                width: image.width,
                height: image.height,
                orientation: orientation
            )
        }

        let layout = ImageProcessor.scaledLayout(
            ImageProcessor.calculateLayout(
                imageWidth: orientedSize.0,
                imageHeight: orientedSize.1,
                options: options
            ),
            maxLongEdge: effectiveMaxLongEdge(
                exportSettings: exportSettings,
                previewMaxDimension: previewMaxDimension
            )
        )
        return CGSize(width: layout.canvasWidth, height: layout.canvasHeight)
    }

    private static func videoRenderSize(
        inputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?
    ) async throws -> CGSize {
        let asset = AVURLAsset(url: inputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw SlideshowVideoProcessingError.cannotLoadVideoTrack
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let orientedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let orientedSize = CGSize(
            width: abs(orientedRect.width),
            height: abs(orientedRect.height)
        )
        let layout = ImageProcessor.scaledLayout(
            ImageProcessor.calculateLayout(
                imageWidth: max(Int(orientedSize.width.rounded()), 1),
                imageHeight: max(Int(orientedSize.height.rounded()), 1),
                options: options
            ),
            maxLongEdge: effectiveMaxLongEdge(
                exportSettings: exportSettings,
                previewMaxDimension: previewMaxDimension
            )
        )

        return CGSize(width: layout.canvasWidth, height: layout.canvasHeight)
    }

    private static func effectiveMaxLongEdge(
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?
    ) -> Int? {
        if let previewMaxDimension {
            return max(Int(previewMaxDimension.rounded(.down)), 1)
        }

        return exportSettings.maxLongEdge
    }

    private static func exactExportLongEdge(
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?
    ) -> Int? {
        guard previewMaxDimension == nil else { return nil }
        return exportSettings.maxLongEdge
    }

    private static func scaledRenderSize(
        _ size: CGSize,
        exactLongEdge: Int?,
        maxLongEdge: Int?
    ) -> CGSize {
        let longEdge = max(size.width, size.height)
        guard longEdge > 0 else {
            return videoCompatibleSize(CGSize(width: 1, height: 1))
        }

        if let exactLongEdge {
            let scale = CGFloat(exactLongEdge) / longEdge
            return videoCompatibleSize(
                CGSize(
                    width: max((size.width * scale).rounded(), 1),
                    height: max((size.height * scale).rounded(), 1)
                )
            )
        }

        if let maxLongEdge, longEdge > CGFloat(maxLongEdge) {
            let scale = CGFloat(maxLongEdge) / longEdge
            return videoCompatibleSize(
                CGSize(
                    width: max((size.width * scale).rounded(), 1),
                    height: max((size.height * scale).rounded(), 1)
                )
            )
        }

        return videoCompatibleSize(size)
    }

    private static func videoCompatibleSize(_ size: CGSize) -> CGSize {
        func evenDimension(_ value: CGFloat) -> CGFloat {
            let dimension = max(Int(value.rounded(.up)), 1)
            return CGFloat(dimension.isMultiple(of: 2) ? dimension : dimension + 1)
        }

        return CGSize(
            width: evenDimension(size.width),
            height: evenDimension(size.height)
        )
    }

    private static func renderImageClip(
        inputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat?,
        renderSize: CGSize
    ) async throws -> SegmentClip {
        let frame = try renderFrame(
            inputURL: inputURL,
            options: options,
            exportSettings: exportSettings,
            previewMaxDimension: previewMaxDimension,
            forcedLayout: try commonImageLayout(
                inputURL: inputURL,
                options: options,
                previewMaxDimension: previewMaxDimension,
                renderSize: renderSize
            )
        )
        let outputURL = temporaryFileURL(pathExtension: "mov")
        let duration = try await writeVideo(
            frames: [frame],
            renderSize: renderSize,
            outputURL: outputURL,
            frameColor: options.frameColorComponents,
            secondsPerPhoto: max(exportSettings.secondsPerPhoto, 0.1)
        )

        return SegmentClip(url: outputURL, duration: duration, renderSize: renderSize)
    }

    private static func renderVideoClip(
        inputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        renderSize: CGSize
    ) async throws -> SegmentClip {
        let asset = AVURLAsset(url: inputURL)
        let sourceDuration = try await asset.load(.duration)
        let sourceSize = try await videoOrientedSize(inputURL: inputURL)
        let layout = commonItemLayout(
            sourceSize: sourceSize,
            renderSize: renderSize,
            options: options
        )
        let targetDuration: CMTime

        switch exportSettings.videoDurationMode {
        case .original:
            targetDuration = sourceDuration
        case .specified:
            targetDuration = CMTime(
                seconds: max(exportSettings.secondsPerPhoto, 0.1),
                preferredTimescale: timeScale
            )
        }

        let sourceURL = temporaryFileURL(pathExtension: "mov")
        let sourceRenderSize = try await VideoProcessor.processSlideshowSegment(
            inputURL: inputURL,
            outputURL: sourceURL,
            options: options,
            exportSettings: exportSettings,
            targetDuration: targetDuration,
            includeOriginalAudio: exportSettings.includeOriginalVideoAudio,
            originalAudioVolume: exportSettings.originalVideoAudioVolume,
            forcedLayout: layout
        )
        let outputURL: URL
        if sourceRenderSize == renderSize {
            outputURL = sourceURL
        } else {
            outputURL = temporaryFileURL(pathExtension: "mov")
            try await normalizeClip(
                inputURL: sourceURL,
                outputURL: outputURL,
                sourceSize: sourceRenderSize,
                targetSize: renderSize,
                duration: targetDuration,
                frameColor: options.frameColorComponents
            )
            try? FileManager.default.removeItem(at: sourceURL)
        }

        return SegmentClip(url: outputURL, duration: targetDuration, renderSize: renderSize)
    }

    private static func normalizeClip(
        inputURL: URL,
        outputURL: URL,
        sourceSize: CGSize,
        targetSize: CGSize,
        duration: CMTime,
        frameColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat)
    ) async throws {
        let asset = AVURLAsset(url: inputURL)
        let composition = AVMutableComposition()

        guard let sourceVideoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw SlideshowVideoProcessingError.cannotLoadVideoTrack
        }

        let timeRange = CMTimeRange(start: .zero, duration: duration)
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for audioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }
            try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        }

        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
        layerInstruction.setTransform(
            filledTrackTransform(
                naturalSize: naturalSize,
                preferredTransform: preferredTransform,
                targetRect: CGRect(origin: .zero, size: targetSize)
            ),
            at: .zero
        )

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = timeRange
        instruction.layerInstructions = [layerInstruction]
        instruction.backgroundColor = CGColor(
            red: frameColor.r,
            green: frameColor.g,
            blue: frameColor.b,
            alpha: frameColor.a
        )

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = targetSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        videoComposition.instructions = [instruction]

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SlideshowVideoProcessingError.cannotCreateExportSession
        }

        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition
        try? FileManager.default.removeItem(at: outputURL)
        try await exportSession.export(to: outputURL, as: .mov)
    }

    private static func commonImageLayout(
        inputURL: URL,
        options: ImageProcessor.Options,
        previewMaxDimension: CGFloat?,
        renderSize: CGSize
    ) throws -> ImageProcessor.Layout {
        let sourceSize: CGSize

        if let previewMaxDimension,
           let previewData = PhotoItem.loadImagePreviewData(from: inputURL, maxDim: previewMaxDimension) {
            sourceSize = CGSize(width: previewData.3, height: previewData.4)
        } else {
            guard let imageSource = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                throw ProcessingError.cannotLoadImage
            }
            let orientation = ImageProcessor.extractOrientation(from: imageSource)
            let orientedSize = ImageProcessor.orientedDimensions(
                width: image.width,
                height: image.height,
                orientation: orientation
            )
            sourceSize = CGSize(width: orientedSize.0, height: orientedSize.1)
        }

        return commonItemLayout(
            sourceSize: sourceSize,
            renderSize: renderSize,
            options: options
        )
    }

    private static func videoOrientedSize(inputURL: URL) async throws -> CGSize {
        let asset = AVURLAsset(url: inputURL)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        guard let track = tracks.first else {
            throw SlideshowVideoProcessingError.cannotLoadVideoTrack
        }

        let naturalSize = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let orientedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized

        return CGSize(
            width: max(abs(orientedRect.width), 1),
            height: max(abs(orientedRect.height), 1)
        )
    }

    private static func commonItemLayout(
        sourceSize: CGSize,
        renderSize: CGSize,
        options: ImageProcessor.Options
    ) -> ImageProcessor.Layout {
        let canvasW = max(renderSize.width, 1)
        let canvasH = max(renderSize.height, 1)
        let paddingRatio = max(options.paddingRatio, 0)
        let padding = floor(max(canvasW, canvasH) * paddingRatio / max(1 + 4.4 * paddingRatio, 1))
        let textAreaHeight = padding * 1.2
        let sideMargin = padding + textAreaHeight
        let availableW = max(canvasW - sideMargin * 2, 1)
        let availableH = max(canvasH - sideMargin * 2, 1)
        let scale = min(
            availableW / max(sourceSize.width, 1),
            availableH / max(sourceSize.height, 1)
        )
        let drawnW = sourceSize.width * scale
        let drawnH = sourceSize.height * scale
        let leewayX = canvasW - drawnW - sideMargin * 2
        let leewayY = canvasH - drawnH - sideMargin * 2

        return ImageProcessor.Layout(
            canvasWidth: max(Int(canvasW.rounded()), 1),
            canvasHeight: max(Int(canvasH.rounded()), 1),
            imageRect: CGRect(
                x: sideMargin + leewayX * options.photoHOffset,
                y: sideMargin + leewayY * (1.0 - options.photoVOffset),
                width: drawnW,
                height: drawnH
            ),
            padding: padding,
            textAreaHeight: textAreaHeight
        )
    }

    private static func stitchClips(
        _ clips: [SegmentClip],
        renderSize: CGSize,
        outputURL: URL,
        exportSettings: ExportSettings
    ) async throws {
        let composition = AVMutableComposition()
        var instructions: [AVVideoCompositionInstructionProtocol] = []
        var audioParameters: [AVAudioMixInputParameters] = []
        var cursor = CMTime.zero

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw SlideshowVideoProcessingError.cannotLoadVideoTrack
            }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw SlideshowVideoProcessingError.cannotCreateComposition
            }

            let timeRange = CMTimeRange(start: .zero, duration: clip.duration)
            try compositionVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: cursor)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            layerInstruction.setTransform(
                filledTrackTransform(
                    naturalSize: naturalSize,
                    preferredTransform: preferredTransform,
                    targetRect: CGRect(origin: .zero, size: renderSize)
                ),
                at: cursor
            )

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: clip.duration)
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            for audioTrack in audioTracks {
                guard let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    continue
                }

                try compositionAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: cursor)
            }

            cursor = cursor + clip.duration
        }

        if let audioURL = resolveAudioURL(from: exportSettings.audioBookmarkData),
           exportSettings.backgroundAudioVolume > 0 {
            let audioAsset = AVURLAsset(url: audioURL)
            guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
                throw SlideshowVideoProcessingError.cannotLoadAudioTrack
            }

            let audioDuration = try await audioAsset.load(.duration)
            guard audioDuration.seconds.isFinite, audioDuration.seconds > 0 else {
                throw SlideshowVideoProcessingError.cannotLoadAudioTrack
            }

            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw SlideshowVideoProcessingError.cannotCreateComposition
            }

            var audioCursor = CMTime.zero
            while audioCursor < cursor {
                let remaining = cursor - audioCursor
                let segmentDuration = min(audioDuration, remaining)
                try compositionAudioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: segmentDuration),
                    of: audioTrack,
                    at: audioCursor
                )
                audioCursor = audioCursor + segmentDuration
            }

            let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
            let targetVolume = Float(min(max(exportSettings.backgroundAudioVolume, 0), 1))
            let totalSeconds = max(cursor.seconds, 0)
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
                    toEndVolume: targetVolume,
                    timeRange: CMTimeRange(start: .zero, duration: fadeInTime)
                )
                parameters.setVolume(targetVolume, at: fadeInTime)
            } else {
                parameters.setVolume(targetVolume, at: .zero)
            }

            if fadeOutDuration > 0 {
                let fadeOutStartSeconds = max(totalSeconds - fadeOutDuration, 0)
                parameters.setVolumeRamp(
                    fromStartVolume: targetVolume,
                    toEndVolume: 0,
                    timeRange: CMTimeRange(
                        start: CMTime(seconds: fadeOutStartSeconds, preferredTimescale: timeScale),
                        duration: CMTime(seconds: fadeOutDuration, preferredTimescale: timeScale)
                    )
                )
            }

            audioParameters.append(parameters)
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        videoComposition.instructions = instructions

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SlideshowVideoProcessingError.cannotCreateExportSession
        }

        exportSession.shouldOptimizeForNetworkUse = false
        exportSession.videoComposition = videoComposition

        if !audioParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioParameters
            exportSession.audioMix = audioMix
        }

        try? FileManager.default.removeItem(at: outputURL)
        try await exportSession.export(to: outputURL, as: .mov)
    }

    private static func normalizedTrackTransform(
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

    private static func filledTrackTransform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        targetRect: CGRect
    ) -> CGAffineTransform {
        guard naturalSize.width > 0,
              naturalSize.height > 0,
              targetRect.width > 0,
              targetRect.height > 0 else {
            return .identity
        }

        let normalizedTransform = normalizedTrackTransform(
            preferredTransform: preferredTransform,
            naturalSize: naturalSize
        )
        let normalizedRect = CGRect(origin: .zero, size: naturalSize)
            .applying(normalizedTransform)
            .standardized
        let scale = max(
            targetRect.width / max(normalizedRect.width, 1),
            targetRect.height / max(normalizedRect.height, 1)
        )

        let scaledTransform = normalizedTransform.concatenating(
            CGAffineTransform(scaleX: scale, y: scale)
        )
        let scaledRect = CGRect(origin: .zero, size: naturalSize)
            .applying(scaledTransform)
            .standardized

        return scaledTransform.concatenating(
            CGAffineTransform(
                translationX: targetRect.midX - scaledRect.midX,
                y: targetRect.midY - scaledRect.midY
            )
        )
    }

    private static func renderFrame(
        inputURL: URL,
        options: ImageProcessor.Options,
        exportSettings: ExportSettings,
        previewMaxDimension: CGFloat? = nil,
        forcedLayout: ImageProcessor.Layout? = nil
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
        let layout = forcedLayout ?? ImageProcessor.calculateLayout(
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
    case noItemsToExport
    case cannotCreateWriter
    case cannotCreatePixelBuffer
    case cannotWriteVideo
    case cannotCreateComposition
    case cannotCreateExportSession
    case cannotLoadVideoTrack
    case cannotLoadAudioTrack

    var errorDescription: String? {
        switch self {
        case .noItemsToExport:
            return "No items are available for slideshow export."
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
