import glob
import os


def detect_all_devices():
    patterns = [
        "/dev/ttyGS*",
        "/dev/ttyUSB*",
        "/dev/ttyACM*",
        "/dev/cu.usbmodem*",
        "/dev/tty.*",
        "/dev/cu.*",
        "/dev/serial/by-id/*"
    ]
    devices = []
    for pattern in patterns:
        devices.extend(glob.glob(pattern))
    return sorted(set(devices))


def detect_usb_device():
    if os.path.exists("/dev/ttyGS0"):
        return "/dev/ttyGS0"
    devices = detect_all_devices()
    return devices[0] if devices else None
