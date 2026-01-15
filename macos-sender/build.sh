#!/bin/bash

set -e

echo "Building Virtual Display Sender as macOS Application..."

cd "$(dirname "$0")"

if ! command -v swift &> /dev/null; then
    echo "Error: Swift is not installed"
    exit 1
fi

./build-app.sh

echo ""
echo "To install to Applications folder:"
echo "  ./install.sh"
echo ""
echo "To run without installing:"
echo "  open \".build/release/Virtual Display.app\""
echo ""
echo "Note: You may need to grant Screen Recording permissions in System Settings > Privacy & Security"
