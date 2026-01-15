#!/bin/bash

set -e

echo "Building Virtual Display Sender as macOS Application..."

cd "$(dirname "$0")"

APP_NAME="Virtual Display"
BUNDLE_ID="com.virtualdisplay.sender"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building executable..."
swift build -c release

echo "Creating app bundle structure..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying executable..."
cp "$BUILD_DIR/VirtualDisplaySender" "$MACOS_DIR/$APP_NAME"

echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "Creating app icon..."
cat > "$RESOURCES_DIR/create-icon.sh" << 'ICONSCRIPT'
#!/bin/bash
mkdir -p AppIcon.iconset
for size in 16 32 128 256 512; do
    size2x=$((size * 2))
    sips -z $size $size --setProperty format png base-icon.png --out "AppIcon.iconset/icon_${size}x${size}.png" 2>/dev/null || true
    sips -z $size2x $size2x --setProperty format png base-icon.png --out "AppIcon.iconset/icon_${size}x${size}@2x.png" 2>/dev/null || true
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
rm -rf AppIcon.iconset
ICONSCRIPT

echo "Setting executable permissions..."
chmod +x "$MACOS_DIR/$APP_NAME"

echo ""
echo "✅ Build complete!"
echo ""
echo "Application bundle created at:"
echo "  $APP_DIR"
echo ""
echo "To install:"
echo "  cp -r \"$APP_DIR\" /Applications/"
echo ""
echo "To run:"
echo "  open \"$APP_DIR\""
echo ""
echo "Note: You'll need to grant Screen Recording permission on first run:"
echo "  System Settings → Privacy & Security → Screen Recording"
