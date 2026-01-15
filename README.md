# DeskExtend – macOS to Raspberry Pi Display Streaming

Turn a Raspberry Pi into a wireless external display for your Mac. Stream your screen, extend your workspace, and reclaim some desk real estate without the expensive external display hardware.

## What Is This?

DeskExtend lets you use a Raspberry Pi as a secondary display for macOS. You can:

- **Stream your Mac's screen** to a Pi-powered display (1080p, 1440p, 4K—depends on your hardware)
- **Connect via USB or WiFi** – automatic fallback between both
- **Extend your workspace** with a virtual display driver
- **Minimal latency** through hardware-accelerated H.264 encoding and decoding
- **Easy setup** with a menu bar app on macOS and a systemd service on the Pi

It's built to be lean and practical. No bloat, just screen streaming that works.

## How It Works

```
macOS (Sender)                    Raspberry Pi (Receiver)
├─ Screen Capture → H.264         ├─ Listen on TCP 5900
├─ HybridTransport                ├─ Decode H.264 (GStreamer)
│  ├─ USB (higher priority)       └─ Output to KMS/framebuffer
│  └─ Network (fallback)
└─ Menu Bar UI
```

The sender captures your screen, encodes it as H.264, and sends it over USB or network. The receiver decodes the stream and displays it. If USB drops, it automatically switches to WiFi.

## Project Structure

```
.
├── DeskExtend/                 # Deprecated SwiftUI version (reference only)
├── macos-sender/               # Modern macOS sender application
│   ├── Sources/
│   │   ├── main.swift          # Entry point
│   │   ├── ConnectionManager.swift  # Handles USB/network connection logic
│   │   ├── HybridTransport.swift    # Chooses best transport (USB or WiFi)
│   │   ├── USBTransport.swift       # USB serial communication
│   │   ├── NetworkTransport.swift   # TCP socket communication
│   │   ├── ScreenCaptureEngine.swift # Screen capture via CoreGraphics
│   │   ├── VideoEncoder.swift       # H.264 encoding (hardware accelerated)
│   │   ├── VirtualDisplay.swift     # Virtual display driver integration
│   │   ├── MenuBarController.swift  # Menu bar UI
│   │   ├── DashboardViewController.swift # Status window
│   │   ├── DisplayManager.swift     # Display enumeration
│   │   ├── ConfigurationManager.swift   # Settings and persistence
│   │   └── Models.swift         # Shared data structures
│   └── Package.swift            # Swift package manifest
├── raspberry-pi-receiver/      # Python receiver application
│   ├── receiver.py              # Main receiver loop, video decode
│   ├── setup.py                 # Installation script
│   ├── install.sh               # Quick install
│   ├── run.sh                   # Run directly
│   ├── setup-service.sh         # Configure systemd service
│   ├── virtual-display.service  # systemd unit file
│   └── waiting.html             # Simple status page
└── build.sh                     # Build helper script
```

## Requirements

### macOS Sender
- macOS 11 or later
- Swift 5.7+
- Xcode 13+ (for development)

### Raspberry Pi Receiver
- Raspberry Pi 4 or 5 (or any ARM board with video output)
- Raspberry Pi OS (Bookworm or later)
- Python 3.9+
- GStreamer with H.264 decoder (hardware or software)

## Getting Started

### Quick Setup (macOS)

```bash
# Build the macOS sender
./build.sh build

# Run directly
./build.sh run

# Or install as an app
./build.sh install
```

The app will appear in your menu bar. You'll need to configure your Raspberry Pi's address first.

### Quick Setup (Raspberry Pi)

```bash
# On your Pi, install dependencies
sudo apt update
sudo apt install -y python3 gstreamer1.0-tools gstreamer1.0-plugins-bad gstreamer1.0-plugins-base gstreamer1.0-libav

# Deploy and run
cd raspberry-pi-receiver
./install.sh
./run.sh
```

For automatic startup, enable the systemd service:

```bash
sudo ./setup-service.sh
sudo systemctl enable deskextend
sudo systemctl start deskextend
```

## Connection Modes

### USB (Preferred)
Plug in a USB-to-serial adapter (or similar) between Mac and Pi. Faster, lower latency, more reliable.

1. Connect Pi to Mac via USB serial device
2. In the app, select "USB" mode and specify the device path (usually `/dev/ttyUSB0`)
3. Click "Connect"

### Network (Fallback)
WiFi connection for wireless streaming. Used automatically if USB isn't available.

1. Ensure Mac and Pi are on the same network
2. In the app, enter the Pi's IP address or hostname
3. Click "Connect"

### Hybrid Mode
Best of both worlds – tries USB first, falls back to WiFi if needed.

## Configuration

Settings are stored in `~/.deskextend/config.json` on macOS:

```json
{
  "autoConnect": false,
  "connectionMode": "hybrid",
  "piAddress": "192.168.1.100",
  "resolution": "1920x1080",
  "fps": 30,
  "bitrate": 8.0
}
```

Edit this file directly or use the menu bar app's settings (if implemented).

## Performance Tuning

**Resolution & FPS**
- 1080p @ 30 fps is the sweet spot for most setups
- 1440p @ 30 fps works well on Pi 4 with hardware decoding
- 4K requires a Pi 5 and good network bandwidth

**Bitrate**
- Default is 8 Mbps – adjust up for higher quality, down if you see lag
- USB is fast enough to handle 15+ Mbps easily
- WiFi (5 GHz) can do 10–12 Mbps; 2.4 GHz lower

**Latency**
- USB: ~30–50 ms
- WiFi: ~50–150 ms (depending on distance/interference)

## Building from Source

### macOS Sender

```bash
cd macos-sender
swift build -c release
```

Binary is at `.build/release/deskextend-sender`.

### Raspberry Pi Receiver

```bash
cd raspberry-pi-receiver
python3 setup.py
```

This installs the Python package and sets up the environment.

## Troubleshooting

**"Can't connect to the Pi"**
- Check the Pi is on and reachable: `ping 192.168.1.100`
- Verify the correct connection mode (USB or network) is selected
- Look for error messages in the app's diagnostics window

**"Stream is choppy / slow"**
- Check CPU usage on both Mac and Pi
- Reduce resolution or FPS if needed
- For network mode, check WiFi signal strength
- GStreamer pipeline on Pi should show which decoder is in use

**"USB device not found"**
- Confirm the adapter is plugged in: `ls /dev/tty*`
- Try different USB ports
- Some adapters need drivers – check the manufacturer's docs

**"Pi receiver won't start"**
- Check systemd logs: `journalctl -u deskextend -n 50`
- Run `./run.sh` directly to see output
- Ensure GStreamer is installed and working: `gst-launch-1.0 --version`

## Known Limitations

- **Single-display only** – currently streams one screen at a time
- **Audio not included** – video only (can be added later)
- **Keyboard/mouse passthrough** – not yet implemented
- **Display sleep** – doesn't wake the Pi display on activity (manual for now)
- **Retina/scaling** – works but scaling on the Pi side is basic

## Development Notes

This project started as a way to repurpose old Raspberry Pis as cheap external displays. The SwiftUI version (`DeskExtend/`) was the initial attempt but proved too heavyweight for a menu bar app. The current Swift Command Line version (`macos-sender/`) is leaner and faster.

Key design decisions:
- **Hybrid transport** – USB when available (deterministic), WiFi as a safety net
- **Hardware encoding/decoding** – critical for smooth 1080p+ streaming
- **H.264 codec** – wide hardware support on both macOS and Pi
- **Menu bar only** – minimal UI footprint, no extra windows unless needed

The receiver's GStreamer pipeline is auto-detected based on available hardware, so it "just works" on different Pi models.

## Contributing

This is a personal project. Feel free to fork it for your own setup. If you find bugs or make improvements, happy to see them, but I'm not actively maintaining this beyond my own use.

## License

MIT – see [LICENSE](LICENSE) for details.

## See Also

- [GStreamer Pipelines](https://gstreamer.freedesktop.org/)
- [macOS Screen Capture APIs](https://developer.apple.com/documentation/screencapturekit)
- [Raspberry Pi Display Output](https://www.raspberrypi.com/documentation/)
