import glob
import os


def detect_all_devices():
    ordered = []
    seen = set()

    preferred = ["/dev/ttyGS0"]
    for path in preferred:
        if os.path.exists(path) and path not in seen:
            seen.add(path)
            ordered.append(path)

    primary_patterns = [
        "/dev/serial/by-id/*",
        "/dev/ttyGS*",
        "/dev/ttyACM*",
        "/dev/ttyUSB*"
    ]

    for pattern in primary_patterns:
        for path in sorted(glob.glob(pattern)):
            if path not in seen:
                seen.add(path)
                ordered.append(path)

    return ordered


def detect_usb_device():
    if os.path.exists("/dev/ttyGS0"):
        return "/dev/ttyGS0"
    devices = detect_all_devices()
    return devices[0] if devices else None
