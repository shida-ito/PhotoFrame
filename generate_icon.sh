#!/bin/bash
# generate_icon.sh — Create AppIcon.icns from PhotoFrame.png
set -euo pipefail

SOURCE_IMAGE="PhotoFrame.png"
ICONSET="AppIcon.iconset"

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "❌ Error: $SOURCE_IMAGE not found."
    exit 1
fi

echo "🎨 Generating iconset..."
mkdir -p "$ICONSET"

# Define sizes (standard macOS icon sizes)
SIZES=(16 32 128 256 512)

for size in "${SIZES[@]}"; do
    # Normal size
    sips -z "$size" "$size" "$SOURCE_IMAGE" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null 2>&1
    # Retina size (@2x)
    double_size=$((size * 2))
    sips -z "$double_size" "$double_size" "$SOURCE_IMAGE" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null 2>&1
done

echo "📦 Converting to .icns..."
# Suppress warning about upscaling if it occurs
iconutil -c icns "$ICONSET" -o AppIcon.icns

echo "🧹 Cleaning up intermediate files..."
rm -rf "$ICONSET"

echo "✅ AppIcon.icns generated successfully!"
