#!/bin/bash

if [ "$EUID" -ne 0 ]; then 
    echo "Please run with sudo for hardware access"
    exit 1
fi

export DISPLAY=:0
export GST_DEBUG=0
export GST_OMX_CONFIG_DIR=/opt/vc/lib

echo "Starting DeskExtend Receiver..."
echo "Listening on port 5900"
echo "Press Ctrl+C to stop"

python3 receiver.py
