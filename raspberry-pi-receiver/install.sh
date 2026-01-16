#!/bin/bash

set -e

echo "Installing DeskExtend Receiver for Raspberry Pi..."

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

echo "Installing system packages..."
apt-get update
apt-get install -y \
    python3 \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-vaapi \
    gstreamer1.0-omx \
    libgstreamer1.0-0 \
    libgstreamer-plugins-base1.0-0 \
    wmctrl

echo "Configuring GPU memory..."
if ! grep -q "^gpu_mem=" /boot/config.txt; then
    echo "gpu_mem=256" >> /boot/config.txt
    echo "GPU memory set to 256MB (reboot required)"
fi

echo "Setting up permissions..."
chmod +x receiver.py
chmod +x run.sh

echo "Installation complete!"
echo ""
echo "To run manually: sudo ./run.sh"
echo "To install as service: sudo ./setup-service.sh"
echo ""
echo "Connect from macOS to: $(hostname -I | awk '{print $1}'):5900"
