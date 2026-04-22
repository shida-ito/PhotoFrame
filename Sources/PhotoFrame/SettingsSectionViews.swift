import SwiftUI

private func resolvedThemeAppearance(_ rawValue: String) -> UIThemeAppearance {
    (UITheme(rawValue: rawValue) ?? .midnight).appearance
}

struct AspectRatioSettings: View {
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @Binding var configuration: FrameConfiguration
    let language: AppLanguage

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible()),
    ]

    private var theme: UIThemeAppearance {
        resolvedThemeAppearance(uiThemeRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "aspectratio")
                    .font(.caption)
                    .foregroundColor(theme.accent)
                Text(L10n.aspectRatio(language))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(AspectRatio.allCases) { ratio in
                    Button(action: { configuration.aspectRatio = ratio }) {
                        Text(ratio.title(language))
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(
                                        configuration.aspectRatio == ratio
                                            ? theme.selectionFill
                                            : Color.white.opacity(0.05)
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        configuration.aspectRatio == ratio ? theme.selectionStroke : Color.clear,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(configuration.aspectRatio == ratio ? .white : .white.opacity(0.6))
                }
            }

            if configuration.aspectRatio == .custom {
                HStack(spacing: 8) {
                    TextField("W", text: $configuration.customWidth)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                    Text(":")
                        .foregroundColor(.white.opacity(0.5))
                    TextField("H", text: $configuration.customHeight)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
            }
        }
    }
}

struct AlignmentSettings: View {
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @Binding var configuration: FrameConfiguration
    let language: AppLanguage

    private var theme: UIThemeAppearance {
        resolvedThemeAppearance(uiThemeRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "hand.tap.fill")
                    .font(.caption)
                    .foregroundColor(theme.accent)
                Text(L10n.photoPosition(language))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.vertical(language))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.to.line")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                    Slider(value: $configuration.photoVOffset, in: 0.0...1.0)
                        .tint(theme.accent)
                    NumericField(value: $configuration.photoVOffset)
                        .frame(width: 45)
                        .font(.caption2)
                    Image(systemName: "arrow.down.to.line")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.horizontal(language))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.to.line")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                    Slider(value: $configuration.photoHOffset, in: 0.0...1.0)
                        .tint(theme.accent)
                    NumericField(value: $configuration.photoHOffset)
                        .frame(width: 45)
                        .font(.caption2)
                    Image(systemName: "arrow.right.to.line")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
    }
}

struct FrameColorSettings: View {
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @Binding var configuration: FrameConfiguration
    let language: AppLanguage

    private var theme: UIThemeAppearance {
        resolvedThemeAppearance(uiThemeRaw)
    }

    private var frameColorBinding: Binding<Color> {
        Binding(
            get: { configuration.colorValue },
            set: { configuration.colorValue = $0 }
        )
    }

    private var photoBorderColorBinding: Binding<Color> {
        Binding(
            get: { configuration.photoBorderColorValue },
            set: { configuration.photoBorderColorValue = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "paintpalette")
                    .font(.caption)
                    .foregroundColor(theme.accent)
                Text(L10n.frameStyle(language))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }

            HStack {
                Label(L10n.color(language), systemImage: "square")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                ColorPicker("", selection: frameColorBinding)
                    .labelsHidden()
            }

            Toggle(L10n.photoBorder(language), isOn: $configuration.photoBorderEnabled)
                .toggleStyle(.switch)

            if configuration.photoBorderEnabled {
                HStack {
                    Label(L10n.borderColor(language), systemImage: "rectangle")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    ColorPicker("", selection: photoBorderColorBinding)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.borderWidth(language))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    HStack {
                        Slider(value: $configuration.photoBorderWidthPercent, in: 0.05...2.0, step: 0.05)
                            .tint(theme.accent)
                        NumericField(value: $configuration.photoBorderWidthPercent)
                            .frame(width: 50)
                            .font(.caption2)
                    }
                }
            }
        }
    }
}

struct TextLayersSettings: View {
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @Binding var configuration: FrameConfiguration
    let language: AppLanguage
    let currentExifInfo: ExifInfo?

    private var theme: UIThemeAppearance {
        resolvedThemeAppearance(uiThemeRaw)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundColor(theme.accent)
                Text(L10n.textLayers(language))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
                    .textCase(.uppercase)
            }

            ForEach($configuration.textLayers) { $layer in
                TextLayerEditorRow(layer: $layer, language: language) {
                    if let index = configuration.textLayers.firstIndex(where: { $0.id == layer.id }) {
                        configuration.textLayers.remove(at: index)
                    }
                }
            }

            Button(action: addLayer) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(L10n.addLayer(language))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(8)
            .background(theme.selectionFill)
            .foregroundColor(theme.accent)
            .cornerRadius(8)

            Text(L10n.tags(language))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))
                .padding(.top, 4)

            if let currentExifInfo, !currentExifInfo.availableMetadataTags.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.dynamicTagHint(language))
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.45))

                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 6) {
                                ForEach(currentExifInfo.availableMetadataTags) { tag in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("{\(tag.name)}")
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.85))
                                        Text(tag.value)
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.5))
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color.white.opacity(0.04))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .frame(maxHeight: 180)
                    }
                    .padding(.top, 6)
                } label: {
                    Text(L10n.photoExifTags(language))
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
    }

    private func addLayer() {
        configuration.textLayers.append(
            TextLayer(
                textTemplate: "{Camera} • {Lens}",
                fontName: "Helvetica Neue",
                fontSizePercent: 1.8,
                textColor: .gray,
                hOffset: 0.5,
                vOffset: 0.9,
                hAlignment: .center
            )
        )
    }
}

struct TextLayerEditorRow: View {
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @AppStorage("fontSelectionDisplayMode") private var fontSelectionDisplayModeRaw = FontSelectionDisplayMode.compact.rawValue
    @Binding var layer: TextLayer
    let language: AppLanguage
    let onRemove: () -> Void

    private var fontSelectionDisplayMode: FontSelectionDisplayMode {
        FontSelectionDisplayMode(rawValue: fontSelectionDisplayModeRaw) ?? .compact
    }

    private var theme: UIThemeAppearance {
        resolvedThemeAppearance(uiThemeRaw)
    }

    private var fontFamilyBinding: Binding<String> {
        Binding(
            get: { FrameSettings.resolvedFontFamilyName(for: layer.fontName) },
            set: { familyName in
                layer.fontName = FrameSettings.resolveFontName(familyName: familyName)
            }
        )
    }

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                DebouncedTextField(
                    placeholder: L10n.textTemplate(language),
                    text: $layer.textTemplate
                )
                .font(.system(size: 12))

                HStack {
                    Label(L10n.color(language), systemImage: "paintpalette")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    ColorPicker("", selection: $layer.textColor)
                        .labelsHidden()
                }

                if fontSelectionDisplayMode == .classic {
                    ClassicFontPicker(selection: fontFamilyBinding, language: language)
                } else {
                    SearchableFontPicker(selection: fontFamilyBinding, language: language)
                }

                FontFacePicker(selection: $layer.fontName, language: language)

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.textSize(language))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    HStack {
                        Slider(value: $layer.fontSizePercent, in: 0.5...5.0, step: 0.1)
                            .tint(theme.accent)
                        NumericField(value: $layer.fontSizePercent)
                            .frame(width: 45)
                            .font(.caption2)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.textPosition(language))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    HStack {
                        Slider(value: $layer.hOffset, in: 0.0...1.0)
                            .tint(theme.accent)
                        NumericField(value: $layer.hOffset)
                            .frame(width: 45)
                            .font(.caption2)
                    }
                    HStack {
                        Slider(value: $layer.vOffset, in: 0.0...1.0)
                            .tint(theme.accent)
                        NumericField(value: $layer.vOffset)
                            .frame(width: 45)
                            .font(.caption2)
                    }
                }

                HStack {
                    Text(L10n.align(language))
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.4))
                    Picker("", selection: $layer.hAlignment) {
                        ForEach(ExifHAlignment.allCases) { alignment in
                            Text(alignment.title(language)).tag(alignment)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Button(action: onRemove) {
                    Text(L10n.removeLayer(language))
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Button(action: { layer.isVisible.toggle() }) {
                    Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(layer.isVisible ? theme.accent : .white.opacity(0.3))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Text(layer.textTemplate.isEmpty ? L10n.emptyLayer(language) : layer.textTemplate)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(layer.isVisible ? .white : .white.opacity(0.3))
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.05))
        .cornerRadius(8)
    }
}

struct ClassicFontPicker: View {
    @Binding var selection: String
    let language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.fontFamily(language))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))

            Picker("", selection: $selection) {
                ForEach(FrameSettings.availableFonts, id: \.self) { fontName in
                    FontFamilyLabel(fontName: fontName)
                        .tag(fontName)
                }
            }
            .labelsHidden()
        }
    }
}

private struct FontFamilyLabel: View {
    let fontName: String

    var body: some View {
        Text(fontName)
            .font(.custom(FrameSettings.resolveFontName(familyName: fontName), size: 12))
            .lineLimit(1)
    }
}

struct SearchableFontPicker: View {
    @AppStorage("uiTheme") private var uiThemeRaw = UITheme.midnight.rawValue
    @Binding var selection: String
    let language: AppLanguage
    @State private var isPresented = false
    @State private var query = ""

    private var theme: UIThemeAppearance {
        resolvedThemeAppearance(uiThemeRaw)
    }

    private var filteredFonts: [String] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return FrameSettings.availableFonts }

        let prefixMatches = FrameSettings.availableFonts.filter {
            $0.lowercased().hasPrefix(trimmedQuery)
        }
        let containsMatches = FrameSettings.availableFonts.filter { fontName in
            let lowercasedName = fontName.lowercased()
            return !lowercasedName.hasPrefix(trimmedQuery) && lowercasedName.contains(trimmedQuery)
        }
        return prefixMatches + containsMatches
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.fontFamily(language))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))

            Button(action: presentPopover) {
                HStack(spacing: 8) {
                    FontFamilyLabel(fontName: selection)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white.opacity(0.4))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isPresented, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField(L10n.searchFonts(language), text: $query)
                        .textFieldStyle(.roundedBorder)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.preview(language))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(selection)
                            .font(.custom(FrameSettings.resolveFontName(familyName: selection), size: 14))
                            .lineLimit(1)
                    }

                    if filteredFonts.isEmpty {
                        Text(L10n.noFontsFound(language))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(filteredFonts, id: \.self) { fontName in
                                    Button(action: { select(fontName) }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: fontName == selection ? "checkmark" : "circle")
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(fontName == selection ? theme.accent : .clear)
                                            FontFamilyLabel(fontName: fontName)
                                                .foregroundColor(.primary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(fontName == selection ? Color.accentColor.opacity(0.12) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(12)
                .frame(width: 320, height: 360)
            }
        }
    }

    private func presentPopover() {
        query = ""
        isPresented = true
    }

    private func select(_ fontName: String) {
        selection = fontName
        isPresented = false
    }
}

struct FontFacePicker: View {
    @Binding var selection: String
    let language: AppLanguage

    private var faceOptions: [FontFaceOption] {
        FrameSettings.faceOptions(for: selection)
    }

    private var selectedFaceBinding: Binding<String> {
        Binding(
            get: {
                FrameSettings.selectedFace(for: selection)?.postScriptName ??
                faceOptions.first?.postScriptName ??
                selection
            },
            set: { selection = $0 }
        )
    }

    private var selectedFaceName: String {
        FrameSettings.resolvedFontFaceName(for: selection)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.fontFace(language))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.4))

            if faceOptions.count <= 1 {
                HStack(spacing: 8) {
                    Text(selectedFaceName)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            } else {
                Picker("", selection: selectedFaceBinding) {
                    ForEach(faceOptions) { face in
                        Text(face.displayName).tag(face.postScriptName)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }
}
