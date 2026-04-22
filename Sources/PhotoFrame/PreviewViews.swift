import AppKit
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
                    Text(item.filename)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
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
