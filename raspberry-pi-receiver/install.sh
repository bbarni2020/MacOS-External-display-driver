#!/bin/bash

set -e

echo "Installing dependencies for Raspberry Pi receiver..."

sudo apt-get update
sudo apt-get install -y \
    gstreamer1.0-tools \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    gstreamer1.0-omx \
    python3-pip \
    libgstreamer1.0-dev \
    libgstreamer-plugins-base1.0-dev

sudo pip3 install --upgrade pip

echo ""
echo "Testing GStreamer installation..."
gst-launch-1.0 --version

echo ""
echo "Installation complete!"
echo "Run the receiver with: python3 receiver.py"
