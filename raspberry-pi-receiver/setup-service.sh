#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

SERVICE_FILE="/etc/systemd/system/deskextend.service"

echo "Installing DeskExtend as system service..."

cat > "$SERVICE_FILE" << 'EOF'
[Unit]
Description=DeskExtend Video Receiver
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/home/pi/deskextend
Environment="DISPLAY=:0"
Environment="GST_DEBUG=0"
Environment="GST_OMX_CONFIG_DIR=/opt/vc/lib"
ExecStart=/usr/bin/python3 /home/pi/deskextend/receiver.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

INSTALL_DIR="/home/pi/deskextend"
mkdir -p "$INSTALL_DIR"
cp receiver.py "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/receiver.py"

systemctl daemon-reload
systemctl enable deskextend.service
systemctl start deskextend.service

echo "Service installed and started!"
echo "Status: systemctl status deskextend"
echo "Logs: journalctl -u deskextend -f"
