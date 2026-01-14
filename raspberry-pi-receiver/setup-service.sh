#!/bin/bash

echo "Setting up Virtual Display Receiver service..."

SERVICE_FILE="virtual-display.service"
INSTALL_DIR="/home/pi/virtual-display"

sudo mkdir -p "$INSTALL_DIR"
sudo cp receiver.py "$INSTALL_DIR/"
sudo chmod +x "$INSTALL_DIR/receiver.py"

sudo cp "$SERVICE_FILE" /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable virtual-display.service

echo ""
echo "Service installed and enabled!"
echo ""
echo "Commands:"
echo "  Start:   sudo systemctl start virtual-display"
echo "  Stop:    sudo systemctl stop virtual-display"
echo "  Status:  sudo systemctl status virtual-display"
echo "  Logs:    sudo journalctl -u virtual-display -f"
echo ""
echo "The service will start automatically on boot."
