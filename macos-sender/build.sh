#!/bin/bash

set -e

echo "Building Virtual Display Sender..."

cd "$(dirname "$0")"

if ! command -v swift &> /dev/null; then
    echo "Error: Swift is not installed"
    exit 1
fi

swift build -c release

echo ""
echo "Build complete!"
echo "Run with: .build/release/VirtualDisplaySender"
echo ""
echo "Note: You may need to grant Screen Recording permissions in System Settings > Privacy & Security"
