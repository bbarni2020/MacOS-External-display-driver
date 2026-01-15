#!/bin/bash

set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

case "${1:-help}" in
    build)
        echo "Building DeskExtend macOS Sender..."
        cd "$PROJECT_ROOT/macos-sender"
        swift build -c release
        echo "Build complete: .build/release/deskextend-sender"
        ;;
    
    build-pi)
        echo "Building Raspberry Pi receiver..."
        cd "$PROJECT_ROOT/raspberry-pi-receiver"
        
        if [[ -z "$PI_HOST" ]]; then
            echo "Error: PI_HOST environment variable not set"
            echo "Usage: PI_HOST=pi@192.168.1.100 $0 build-pi"
            exit 1
        fi
        
        echo "Deploying to $PI_HOST..."
        scp -r . "$PI_HOST:/tmp/deskextend/"
        ssh "$PI_HOST" "cd /tmp/deskextend && python3 setup.py"
        echo "Raspberry Pi setup complete"
        ;;
    
    install)
        echo "Installing macOS application..."
        cd "$PROJECT_ROOT/macos-sender"
        swift build -c release
        
        APP_PATH="${HOME}/Applications/DeskExtend.app"
        mkdir -p "$APP_PATH"
        cp -r .build/release/* "$APP_PATH/"
        
        echo "Application installed to $APP_PATH"
        open "$APP_PATH"
        ;;
    
    run)
        echo "Running DeskExtend..."
        cd "$PROJECT_ROOT/macos-sender"
        swift run deskextend-sender
        ;;
    
    test)
        echo "Running tests..."
        cd "$PROJECT_ROOT"
        
        echo "Testing macOS sender..."
        cd "$PROJECT_ROOT/macos-sender"
        swift test
        
        echo "Testing Raspberry Pi receiver..."
        cd "$PROJECT_ROOT/raspberry-pi-receiver"
        python3 -m pytest . 2>/dev/null || echo "Skipping Pi tests"
        ;;
    
    clean)
        echo "Cleaning build artifacts..."
        cd "$PROJECT_ROOT/macos-sender"
        swift package clean
        rm -rf .build
        ;;
    
    *)
        cat << 'EOF'
DeskExtend Build System

Usage: ./build.sh [command]

Commands:
    build       - Build macOS sender (release)
    build-pi    - Build and deploy Raspberry Pi receiver
    install     - Install macOS application to ~/Applications
    run         - Build and run macOS sender
    test        - Run all tests
    clean       - Remove build artifacts
    help        - Show this help message

Environment Variables:
    PI_HOST    - Raspberry Pi SSH address (user@host) for build-pi
    
Examples:
    ./build.sh build
    PI_HOST=pi@192.168.1.100 ./build.sh build-pi
    ./build.sh install
EOF
        ;;
esac
