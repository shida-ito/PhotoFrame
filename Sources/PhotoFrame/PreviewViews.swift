import AppKit
import AVKit
import SwiftUI

struct LivePreviewCanvas: View {
    let image: NSImage
    let textLayers: [ImageProcessor.PreviewTextLayer]

    var body: some View {
        GeometryReader { geometry in
            let sourceSize = CGSize(
                width: max(image.size.width, 1),
                height: max(image.size.height, 1)
            )
            let scale = min(
                geometry.size.width / sourceSize.width,
                geometry.size.height / sourceSize.height
            )
            let fittedSize = CGSize(
                width: sourceSize.width * scale,
                height: sourceSize.height * scale
            )
            let offset = CGPoint(
                x: (geometry.size.width - fittedSize.width) / 2.0,
                y: (geometry.size.height - fittedSize.height) / 2.0
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: fittedSize.width, height: fittedSize.height)

                ZStack(alignment: .topLeading) {
                    ForEach(textLayers) { layer in
                        Text(layer.text)
                            .font(.custom(layer.fontName, size: layer.fontSize))
                            .foregroundStyle(
                                Color(
                                    nsColor: NSColor(
                                        srgbRed: layer.textColorComponents.r,
                                        green: layer.textColorComponents.g,
                                        blue: layer.textColorComponents.b,
                                        alpha: layer.textColorComponents.a
                                    )
                                )
                            )
                            .fixedSize()
                            .position(
                                x: layer.origin.x + layer.size.width / 2.0,
                                y: sourceSize.height - layer.origin.y - layer.size.height / 2.0
                            )
                    }
                }
                .frame(width: sourceSize.width, height: sourceSize.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .allowsHitTesting(false)
            }
            .frame(width: fittedSize.width, height: fittedSize.height, alignment: .topLeading)
            .offset(x: offset.x, y: offset.y)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}

struct LiveVideoPreviewCanvas: View {
    let backgroundImage: NSImage
    let videoURL: URL
    let videoComposition: AVVideoComposition?
    let compositionSignature: String
    let imageRect: CGRect
    let textLayers: [ImageProcessor.PreviewTextLayer]

    var body: some View {
        GeometryReader { geometry in
            let sourceSize = CGSize(
                width: max(backgroundImage.size.width, 1),
                height: max(backgroundImage.size.height, 1)
            )
            let scale = min(
                geometry.size.width / sourceSize.width,
                geometry.size.height / sourceSize.height
            )
            let fittedSize = CGSize(
                width: sourceSize.width * scale,
                height: sourceSize.height * scale
            )
            let offset = CGPoint(
                x: (geometry.size.width - fittedSize.width) / 2.0,
                y: (geometry.size.height - fittedSize.height) / 2.0
            )
            let videoFrame = CGRect(
                x: imageRect.minX * scale,
                y: (sourceSize.height - imageRect.maxY) * scale,
                width: imageRect.width * scale,
                height: imageRect.height * scale
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: backgroundImage)
                    .resizable()
                    .frame(width: fittedSize.width, height: fittedSize.height)

                LoopingVideoPlayerView(
                    url: videoURL,
                    videoComposition: videoComposition,
                    compositionSignature: compositionSignature
                )
                    .frame(width: videoFrame.width, height: videoFrame.height)
                    .clipShape(Rectangle())
                    .offset(x: videoFrame.minX, y: videoFrame.minY)

                ZStack(alignment: .topLeading) {
                    ForEach(textLayers) { layer in
                        Text(layer.text)
                            .font(.custom(layer.fontName, size: layer.fontSize))
                            .foregroundStyle(
                                Color(
                                    nsColor: NSColor(
                                        srgbRed: layer.textColorComponents.r,
                                        green: layer.textColorComponents.g,
                                        blue: layer.textColorComponents.b,
                                        alpha: layer.textColorComponents.a
                                    )
                                )
                            )
                            .fixedSize()
                            .position(
                                x: layer.origin.x + layer.size.width / 2.0,
                                y: sourceSize.height - layer.origin.y - layer.size.height / 2.0
                            )
                    }
                }
                .frame(width: sourceSize.width, height: sourceSize.height, alignment: .topLeading)
                .scaleEffect(scale, anchor: .topLeading)
                .allowsHitTesting(false)
            }
            .frame(width: fittedSize.width, height: fittedSize.height, alignment: .topLeading)
            .offset(x: offset.x, y: offset.y)
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
    }
}

struct SlideshowVideoPreviewCanvas: View {
    let url: URL
    var isMuted = true
    var loops = true
    var onPlaybackEnded: (() -> Void)? = nil

    @State private var sourceSize: CGSize?

    var body: some View {
        GeometryReader { geometry in
            let resolvedSize = sourceSize ?? CGSize(
                width: max(geometry.size.width, 1),
                height: max(geometry.size.height, 1)
            )
            let scale = min(
                geometry.size.width / max(resolvedSize.width, 1),
                geometry.size.height / max(resolvedSize.height, 1)
            )
            let fittedSize = CGSize(
                width: resolvedSize.width * scale,
                height: resolvedSize.height * scale
            )

            LoopingVideoPlayerView(
                url: url,
                isMuted: isMuted,
                loops: loops,
                onPlaybackEnded: onPlaybackEnded
            )
            .frame(width: fittedSize.width, height: fittedSize.height)
            .position(x: geometry.size.width / 2.0, y: geometry.size.height / 2.0)
            .task(id: url) {
                sourceSize = await Self.loadDisplaySize(from: url)
            }
        }
    }

    private static func loadDisplaySize(from url: URL) async -> CGSize? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
              let naturalSize = try? await track.load(.naturalSize),
              let preferredTransform = try? await track.load(.preferredTransform) else {
            return nil
        }

        let rect = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        return CGSize(width: max(abs(rect.width), 1), height: max(abs(rect.height), 1))
    }
}

struct LoopingVideoPlayerView: NSViewRepresentable {
    let url: URL
    var videoComposition: AVVideoComposition? = nil
    var compositionSignature: String = ""
    var isMuted: Bool = true
    var loops: Bool = true
    var onPlaybackEnded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsSharingServiceButton = false
        context.coordinator.attach(
            to: view,
            url: url,
            videoComposition: videoComposition,
            compositionSignature: compositionSignature,
            isMuted: isMuted,
            loops: loops,
            onPlaybackEnded: onPlaybackEnded
        )
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        context.coordinator.attach(
            to: nsView,
            url: url,
            videoComposition: videoComposition,
            compositionSignature: compositionSignature,
            isMuted: isMuted,
            loops: loops,
            onPlaybackEnded: onPlaybackEnded
        )
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.player = nil
    }

    @MainActor
    final class Coordinator {
        private var currentURL: URL?
        private var currentCompositionSignature = ""
        private var currentMuted = true
        private var currentLoops = true
        private var player: AVPlayer?
        private var looper: AVPlayerLooper?
        private var playbackEndedObserver: NSObjectProtocol?
        private var playbackEndedHandler: (() -> Void)?

        func attach(
            to view: AVPlayerView,
            url: URL,
            videoComposition: AVVideoComposition?,
            compositionSignature: String,
            isMuted: Bool,
            loops: Bool,
            onPlaybackEnded: (() -> Void)?
        ) {
            playbackEndedHandler = onPlaybackEnded

            guard currentURL != url ||
                    player == nil ||
                    currentMuted != isMuted ||
                    currentLoops != loops ||
                    currentCompositionSignature != compositionSignature else {
                view.player = player
                return
            }

            stop()

            let playerItem = AVPlayerItem(url: url)
            playerItem.videoComposition = videoComposition
            let player: AVPlayer
            let looper: AVPlayerLooper?

            if loops {
                let queuePlayer = AVQueuePlayer()
                queuePlayer.isMuted = isMuted
                queuePlayer.actionAtItemEnd = .none
                player = queuePlayer
                looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
            } else {
                let singlePlayer = AVPlayer(playerItem: playerItem)
                singlePlayer.isMuted = isMuted
                singlePlayer.actionAtItemEnd = .pause
                player = singlePlayer
                looper = nil
                playbackEndedObserver = NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.playbackEndedHandler?()
                    }
                }
            }

            player.isMuted = isMuted

            self.currentURL = url
            self.currentCompositionSignature = compositionSignature
            self.currentMuted = isMuted
            self.currentLoops = loops
            self.player = player
            self.looper = looper

            view.player = player
            player.play()
        }

        func stop() {
            player?.pause()
            player = nil
            looper = nil
            if let playbackEndedObserver {
                NotificationCenter.default.removeObserver(playbackEndedObserver)
                self.playbackEndedObserver = nil
            }
            currentURL = nil
            currentCompositionSignature = ""
            currentMuted = true
            currentLoops = true
            playbackEndedHandler = nil
        }
    }
}

struct PhotoRowView: View {
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @ObservedObject var item: PhotoItem
    let isSelected: Bool
    let language: AppLanguage
    let onSelect: () -> Void
    let onRemove: () -> Void
    let dragProvider: () -> NSItemProvider

    private var theme: UIThemeAppearance {
        (UITheme(rawValue: uiThemeRaw) ?? .midnight).appearance
    }

    private var currentStatusColor: Color {
        switch item.status {
        case .pending:
            return .white.opacity(0.4)
        case .processing:
            return theme.accent
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Group {
                    if let thumb = item.thumbnail {
                        Image(nsImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .overlay(ProgressView().controlSize(.small))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: item.mediaKind.isVideo ? "video.fill" : "photo")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.45))
                        Text(item.filename)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Text(item.status.label(language))
                        .font(.caption2)
                        .foregroundColor(currentStatusColor)
                }
                Spacer()
            }
            .padding(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag(dragProvider)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? theme.selectionFill : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? theme.selectionStroke : Color.clear, lineWidth: 1)
        )
        .overlay(alignment: .trailing) {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.3))
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
    }
}

struct FullscreenSlideshowPreview: View {
    let videoURL: URL?
    let isMuted: Bool
    let loops: Bool
    let language: AppLanguage
    let isPreparingNextGroup: Bool
    let onPlaybackEnded: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()

            if let videoURL {
                LoopingVideoPlayerView(
                    url: videoURL,
                    isMuted: isMuted,
                    loops: loops,
                    onPlaybackEnded: onPlaybackEnded
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if isPreparingNextGroup {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.white)
                    Text(L10n.preparingNextGroup(language))
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding(28)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18))
            }

            Button(action: onClose) {
                Label(L10n.closeFullscreenPreview(language), systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55), in: Capsule())
                    .foregroundColor(.white)
            }
            .buttonStyle(.plain)
            .padding(24)
        }
    }
}
