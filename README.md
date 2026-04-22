# PhotoFrame

Stylish and minimal photo framing application for macOS. Add elegant borders and customizable EXIF-based text overlays to your photographs.

![App Icon](PhotoFrame.png)
![App Screenshot](AppScreenShot.png)

## 📋 Features

- **Batch Processing**: Frame multiple photos at once with consistent settings.
- **Flexible Frame Layout**: Choose from standard ratios (1:1, 4:5, 3:2, 16:9, and more) or define your own custom ratio.
- **Granular Position Control**:
    - Use precision sliders to position the photo both **vertically and horizontally** inside the frame.
    - Adjust frame width from `0` upward for anything from borderless layouts to wide margins.
- **Text Layers**:
    - Add multiple text layers.
    - Use EXIF tags such as `{Camera}`, `{Lens}`, `{Focal}`, `{FStop}`, `{Shutter}`, `{ISO}`, and `{Date}` inside each template.
    - Control font, color, size, X/Y position, alignment, and visibility per layer.
- **Photo Groups**: Organize photos into groups in the left panel and apply one shared layout setting set per group.
- **Workspace Restore**: Reopen the latest group structure, settings, and photo assignments the next time you launch the app.
- **Fast Interactive Preview**: Cached previews and live text overlays keep text editing and positioning responsive.
- **Preset Management**: Save, rename, delete, and clear reusable layout presets.
- **Flexible Selection**: Finder-standard multi-selection (`Shift+Click`, `Cmd+Click`) for selective batch processing.
- **Preferences**: Choose the UI language (English / Japanese) and switch the font picker between `Search` and `Full List` modes.
- **Multi-Window Workflow**: Open multiple windows to work on different photo sets in parallel.

## 🚀 Getting Started

### Prerequisites

- macOS 14.0+
- Xcode Command Line Tools (for `swift build`)

### Build and Install

Run the provided build script to compile the application and bundle the resources (including the app icon):

```bash
bash build_app.sh
```

Once complete, you will find `PhotoFrame.app` in the project root.

## 📖 Manual

### 1. Adding Photos
- **Drag & Drop**: Simply drag JPEG files from Finder and drop them anywhere in the left panel.
- **Browse**: Click the "+" button or the empty state zone to select files via the file picker.

### 2. Selection & Preview
- **Groups**: Use the folder rows in the left panel to separate photos into groups. Every photo in a group uses that group's settings when previewing and exporting.
- **Group Controls**: Add or rename groups from the controls at the top of the left panel.
- **Move to Group**: Select one or more photos, then use **Move to Group** or drag the selected photos onto another group.
- **Clear Photos / Undo Clear**: Clear only the photos while keeping your groups, then restore the most recent clear with **Undo Clear** if needed.
- **Multi-Selection**: Use macOS standard controls to select items in the list (**Click** to select one, **Cmd+Click** to toggle, **Shift+Click** for range selection).
- **Preview**: The preview panel shows the first photo in your current selection.
- Most settings update the preview instantly, allowing you to fine-tune the look before processing.
- **Preview Quality**: Use the quality picker in the settings panel to trade speed for detail.
- **Multiple Windows**: Use **File > New Window** or `Cmd+N` to open another working window.

### 3. Configuring Frame & Text
- **Group Settings**: The settings panel always edits the currently selected group. Use separate groups when you want different layouts for different subsets of photos.
- **Aspect Ratio**: Select a grid option for the outer frame. If using "Custom", enter the ratio values (e.g., `4:5`).
- **Photo Position**: Use the Vertical and Horizontal sliders in the "Photo Position" section to offset the image within its designated area.
- **Frame Width**: Adjust the amount of space around the image. Set it to `0` for a borderless edge.
- **Text Layers**:
    - Add one or more layers in the "Text Layers" section.
    - Enter a template such as `{Camera} • {Lens}`.
    - Change font, color, text size, X/Y position, and alignment for each layer.
    - Toggle visibility with the eye icon, or remove a layer entirely.
- **Available Tags**: `{Camera}`, `{Lens}`, `{Focal}`, `{FStop}`, `{Shutter}`, `{ISO}`, `{Date}`.

### 4. Presets & Preferences
- **Save Preset**: Save the current layout from the preset menu in the settings header.
- **Rename Preset**: Open a saved preset entry and choose **Rename Preset...**.
- **Delete Preset**: Remove a single preset or clear them all from the same menu.
- **Preferences**: Open **PhotoFrame > Settings...** to:
    - switch the display language between English and Japanese
    - choose the font picker mode: `Search` or `Full List`

### 5. Processing
- **Process Sel (...)**: Click this to process and export only the photos currently selected in the list (the count is shown in the button).
- **Process All**: Click this to process every photo in your list, regardless of selection.
- Select an output directory in the dialog.
- The app will save your framed photos as new JPEGs prefixed with `framed_`.

## 🛡️ Security & Distribution

This application is built as an independent tool and is not signed with an Apple Developer certificate. When running it for the first time on another Mac, you may encounter a macOS Gatekeeper warning.

### How to Open
1. Locate `PhotoFrame.app` in Finder.
2. **Right-click (or Control-click)** the app icon and select **Open**.
3. A dialog will appear asking for confirmation; click **Open**.

Alternatively, if you see a "damaged" warning or it fails to open, you can remove the quarantine attribute via Terminal:
```bash
xattr -cr PhotoFrame.app
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

Developed by [shida-ito](https://github.com/shida-ito)
