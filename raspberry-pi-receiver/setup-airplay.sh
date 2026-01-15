#!/bin/bash

echo "Installing AirPlay receiver (UxPlay)..."

sudo apt-get update
sudo apt-get install -y cmake libssl-dev libplist-dev libavahi-compat-libdnssd-dev
sudo apt-get install -y libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev
sudo apt-get install -y gstreamer1.0-plugins-good gstreamer1.0-plugins-bad
sudo apt-get install -y gstreamer1.0-libav gstreamer1.0-tools

cd /tmp
git clone https://github.com/FDH2/UxPlay.git
cd UxPlay
mkdir -p build
cd build
cmake ..
make -j4
sudo make install

echo ""
echo "Installation complete!"
echo "Run: python3 airplay-receiver.py"
echo "Or with custom name: python3 airplay-receiver.py -n 'My Display'"
