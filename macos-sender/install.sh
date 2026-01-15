#!/bin/bash

set -e

echo "Installing Virtual Display to Applications folder..."

cd "$(dirname "$0")"

if [ ! -d ".build/release/Virtual Display.app" ]; then
    echo "Error: Application not built yet."
    echo "Run ./build-app.sh first"
    exit 1
fi

if [ -d "/Applications/Virtual Display.app" ]; then
    echo "Removing existing installation..."
    rm -rf "/Applications/Virtual Display.app"
fi

echo "Copying to Applications..."
cp -r ".build/release/Virtual Display.app" /Applications/

echo ""
echo "✅ Installation complete!"
echo ""
echo "To launch:"
echo "  1. Open Spotlight (Cmd+Space)"
echo "  2. Type 'Virtual Display'"
echo "  3. Press Enter"
echo ""
echo "Or double-click in Applications folder"
echo ""
echo "First run:"
echo "  - macOS will ask for Screen Recording permission"
echo "  - Go to System Settings → Privacy & Security → Screen Recording"
echo "  - Enable 'Virtual Display'"
echo "  - Restart the app"
echo ""
echo "The app will appear as a menu bar icon (top-right)"
