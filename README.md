# PhotoFrame

Stylish and minimal photo framing application for macOS. Add elegant borders and customizable metadata-based text overlays to photos and videos.

![App Icon](PhotoFrame.png)
![App Screenshot](AppScreenShot.png)

## 📋 Features

- **Batch Export**: Frame multiple photos and videos at once with consistent settings.
- **Flexible Frame Layout**: Choose from standard ratios (1:1, 4:5, 3:2, 16:9, and more) or define your own custom ratio.
- **Granular Position Control**:
    - Use precision sliders to position the photo both **vertically and horizontally** inside the frame.
    - Adjust frame width from `0` upward for anything from borderless layouts to wide margins.
- **Photo Border**: Add an optional extra border that follows the exact photo ratio, with configurable color and width.
- **Text Layers**:
    - Add multiple text layers.
    - Use EXIF tags such as `{Camera}`, `{Lens}`, `{Focal}`, `{FStop}`, `{Shutter}`, `{ISO}`, `{Date}`, `{Year}`, `{Month}`, and `{Day}` inside each template.
    - You can also enter any tag name found in the current photo as `{TagName}`.
    - Control font, color, size, X/Y position, alignment, and visibility per layer.
- **Photo Groups**: Organize photos into groups in the left panel, drag to reorder them, and apply one shared layout setting set per group.
- **Per-Group Slideshow Settings**: Each group can keep its own slideshow timing, audio file, and fade-in / fade-out settings.
- **Slideshow Preview & Export**: Switch the preview between single-photo mode and slideshow mode, add audio, preview fade timing, and export the selected group as a MOV slideshow.
- **Fullscreen Slideshow**: Play the slideshow preview in fullscreen, with optional automatic advance to the next group.
- **Group Settings Transfer**: Export or import settings for a single group, or transfer all group settings at once from the File menu.
- **Workspace Restore**: Reopen the latest group structure, settings, and photo assignments the next time you launch the app.
- **Fast Interactive Preview**: Cached previews and live text overlays keep text editing and positioning responsive.
- **Video Preview & Export**: Preview MOV/MP4 clips inside the frame layout, then export them with the frame and text burned into every frame as MOV.
- **Preset Management**: Presets are shown in A-Z order, support hover preview before click-to-apply, and can be saved, overwritten, renamed, deleted, imported, exported, and cleared.
- **Flexible Selection**: Finder-standard multi-selection (`Shift+Click`, `Cmd+Click`) plus `↑` / `↓` keyboard navigation for selective batch processing.
- **Preferences**: Choose the UI language, color mode (`Midnight`, `Graphite`, `Black`, `Paper`, `Forest`), and font picker mode from `PhotoFrame > Settings...`.
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
- **Drag & Drop**: Simply drag JPEG, MOV, or MP4 files from Finder and drop them anywhere in the left panel.
- **Browse**: Click the "+" button or the empty state zone to select files via the file picker.

### 2. Selection & Preview
- **Groups**: Use the folder rows in the left panel to separate photos into groups. Every photo in a group uses that group's settings when previewing and exporting.
- **Group Reorder**: Drag a group row onto another group row to reorder the group list with the mouse.
- **Top Controls**: Use the controls at the top of the left panel to add photos and add groups.
- **Group Row Menu**: Rename or delete a group from the `...` menu on each group row.
- **Move to Group**: Select one or more photos, then drag the selected photos onto another group.
- **Drop Into Group**: Drop JPEG, MOV, or MP4 files directly onto a group row to add them to that group.
- **Clear Photos / Undo Clear**: Clear only the photos while keeping your groups, then restore the most recent clear with **Undo Clear** if needed.
- **Delete Selected Photos**: After multi-selecting photos, click the `×` button on any selected photo row to remove the whole selection in one action.
- **Multi-Selection**: Use macOS standard controls to select items in the list (**Click** to select one, **Cmd+Click** to toggle, **Shift+Click** for range selection).
- **Keyboard Navigation**: After selecting the photo list, use `↑` / `↓` to move the current item selection up and down.
- **Preview**: The preview panel shows the first item in your current selection. Video items play in-place inside the framed preview.
- **Slideshow Mode**: Switch the preview header between `Photo` and `Slideshow`. Slideshow mode previews the current group's photo order and uses that same group-based flow for MOV export.
- **Photo Order**: Drag photo rows within a group to change slideshow order, or drag them onto another group to move them there.
- Most settings update the preview instantly, allowing you to fine-tune the look before processing.
- **Preview Quality**: Use the quality picker in the settings panel to trade speed for detail, from `Fast (400px)` up to `4K (3840px)`.
- **Multiple Windows**: Use **File > New Window** or `Cmd+N` to open another working window.

### 3. Configuring Frame & Text
- **Group Settings**: The settings panel always edits the currently selected group. Use separate groups when you want different layouts for different subsets of photos.
- **Slideshow Settings**: In slideshow preview mode, set seconds per photo, choose an audio file, and adjust fade-in / fade-out per group.
- **Aspect Ratio**: Select a grid option for the outer frame. If using "Custom", enter the ratio values (e.g., `4:5`).
- **Photo Position**: Use the Vertical and Horizontal sliders in the "Photo Position" section to offset the image within its designated area.
- **Frame Width**: Adjust the amount of space around the image. Set it to `0` for a borderless edge.
- **Photo Border**: In the "Frame Style" section, enable `Show Photo Border` to add a second border around the photo itself. The border always follows the photo's own ratio, and you can change both color and width.
- **Text Layers**:
    - Add one or more layers in the "Text Layers" section.
    - Enter a template such as `{Camera} • {Lens}`.
    - Change font, color, text size, X/Y position, and alignment for each layer.
    - Toggle visibility with the eye icon, or remove a layer entirely.
- **Available Tags**: `{Camera}`, `{Lens}`, `{Focal}`, `{FStop}`, `{Shutter}`, `{ISO}`, `{Date}`, `{Year}`, `{Month}`, `{Day}`.
- **Current Photo Tags**: The Text Layers section can show the actual metadata tag names found in the current preview photo.

### 4. Presets & Preferences
- **Preset List**: Saved presets are shown in alphabetical order in the preset popover.
- **Preset Preview**: Hover over a preset to preview it temporarily on the current group, then click to apply it.
- **Save Preset**: Save the current layout from the preset menu in the settings header.
- **Import / Export / Paste Presets**: Share presets as readable JSON files, import them from disk, or paste preset text directly.
- **Overwrite Preset**: Use the `...` menu on a preset row to replace an existing preset with the current settings.
- **Rename Preset**: Open the `...` menu on a preset row and choose **Rename Preset...**.
- **Delete Preset**: Remove a single preset or clear them all from the same menu.
- **Group Settings Export / Import**: Use the `...` menu on each group row for single-group settings, or use **File** menu commands to export or import all group settings together.
- **Preferences**: Open **PhotoFrame > Settings...** to:
    - switch the display language between English and Japanese
    - choose the UI color mode: `Midnight`, `Graphite`, `Black`, `Paper`, or `Forest`
    - choose the font picker mode: `Search` or `Full List`
    - choose whether fullscreen slideshow playback advances automatically to the next group

### 5. Export
- **Export Sel (...)**: Click this to export only the photos currently selected in the list (the count is shown in the button).
- **Export All**: Click this to export every photo in your list, regardless of selection.
- **Export Settings**: Before choosing the destination folder, a dialog lets you set output format, image size, `Long Edge Custom`, JPEG quality, filename prefix, and whether EXIF / metadata should be copied.
- **Video Export**: Video items are exported as `.mov`. The selected image size setting also scales video exports, and audio is preserved when the source file contains audio.
- **Slideshow Export**: In slideshow preview mode, export works per group. `Current Group` exports the full current group's photo order as one MOV slideshow, and `All Groups` exports one slideshow MOV per group.
- Select an output directory in the dialog.
- The app saves files using the selected format and filename prefix.

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
