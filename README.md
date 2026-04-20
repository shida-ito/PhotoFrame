# PhotoFrame

Stylish and minimal photo framing application for macOS. Automatically add elegant borders and EXIF metadata overlays to your photographs.

![App Icon](PhotoFrame.png)

## 📋 Features

- **Batch Processing**: Frame multiple photos at once with consistent settings.
- **Dynamic Aspect Ratios**: Choose from standard ratios (1:1, 4:5, 3:2, 16:9) or define your own custom ratio.
- **Granular Layout Control**: 
    - Use precision sliders to position your photo vertically within the frame.
    - Adjust the EXIF text overlay position and horizontal alignment (Left, Center, Right).
- **Custom Typography**: Select from high-quality fonts with real-time typeface previews.
- **Smart EXIF Overlay**: Toggle specific metadata fields (Camera, Lens, Focal Length, F-Stop, Shutter Speed, ISO).
- **Pro Aesthetics**: Automatic icon generation and a sleek, modern dark-mode interface.

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

### 2. Previewing
- Click on any photo in the list to see a live preview in the center panel. 
- Most settings will update the preview instantly, allowing you to fine-tune the look before processing.

### 3. Configuring Layout
- **Aspect Ratio**: Select a grid option for the outer frame. If using "Custom", enter the ratio values (e.g., `4:5`).
- **Photo Position**: Use the slider in the "Positioning" section to move the photo up or down within its designated area.
- **EXIF Fields**: Toggle which metadata elements you want to display. Each field is represented by an interactive chip.
- **EXIF Position**: Adjust the vertical position slider to place the text overlay exactly where it fits best on your frame.

### 4. Customizing Style
- **Colors**: Use the color pickers to choose your frame and text colors. White frames with grey text are the classic choice.
- **Font**: Choose a font from the dropdown. Each entry shows the actual typeface to help your selection.
- **Text Size**: Scale the EXIF text globally relative to the frame size.

### 5. Processing
- **Process Sel**: Click this to process and export only the photo currently selected in the preview.
- **Process All**: Click this to process all photos in your list.
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

---

Developed by [shida-ito](https://github.com/shida-ito)
