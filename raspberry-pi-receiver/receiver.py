#!/usr/bin/env python3

import argparse
import logging
import os
import signal
import sys

from deskextend_receiver.core import VideoReceiver
from deskextend_receiver.services.deps import install_dependencies
from deskextend_receiver.services.usb_gadget import setup_usb_gadget
from deskextend_receiver.utils.devices import detect_all_devices, detect_usb_device

logger = logging.getLogger(__name__)
receiver = None


def configure_logging(level_name):
    level = getattr(logging, level_name.upper(), logging.INFO)
    logging.getLogger().setLevel(level)
    logger.setLevel(level)


def available_interfaces():
    try:
        return sorted([name for name in os.listdir("/sys/class/net") if name != "lo"])
    except Exception:
        return []


def signal_handler(sig, frame):
    if receiver:
        receiver.stop()
    sys.exit(0)


def build_parser():
    parser = argparse.ArgumentParser(description="macOS External Display Receiver")
    parser.add_argument(
        "--mode",
        choices=["network", "ethernet", "usb", "hybrid", "all"],
        default="all",
        help="Connection mode: network (Wi-Fi/Ethernet TCP), ethernet (wired-only TCP), usb (serial), hybrid (USB+Ethernet failover), or all (USB+network)"
    )
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (network/ethernet/hybrid/all mode)")
    parser.add_argument("--port", type=int, default=5900, help="TCP port (network/ethernet/hybrid/all mode)")
    parser.add_argument("--usb-device", help="USB serial device path (use /dev/ttyGS0 for Pi gadget mode)")
    parser.add_argument("--eth-interface", help="Force Ethernet interface name for ethernet/hybrid mode (e.g. eth0)")
    parser.add_argument("--name", help="Device name for identification (default: RaspberryPi)")
    parser.add_argument("--log-level", choices=["DEBUG", "INFO", "WARNING", "ERROR"], default="INFO", help="Logging verbosity")
    parser.add_argument("--install", action="store_true", help="Install system and Python dependencies")
    parser.add_argument("--setup-usb", action="store_true", help="Setup USB gadget mode (requires root)")
    return parser


def pick_usb_device(mode, usb_device):
    if mode not in ["usb", "hybrid", "all"] or usb_device:
        return usb_device

    if os.path.exists("/dev/ttyGS0"):
        logger.info("USB gadget mode detected: /dev/ttyGS0")
        return "/dev/ttyGS0"

    auto_device = detect_usb_device()
    if auto_device:
        logger.info(f"Auto-detected USB device: {auto_device}")
        return auto_device

    if mode == "usb":
        devices = detect_all_devices()
        if not devices:
            print("No USB devices found")
            sys.exit(1)

        print("\nAvailable USB devices:")
        for idx, dev in enumerate(devices, 1):
            print(f"  {idx}. {dev}")

        while True:
            selection = input(f"\nSelect device (1-{len(devices)}): ").strip()
            try:
                idx = int(selection) - 1
            except ValueError:
                print(f"Invalid input. Please enter a number between 1 and {len(devices)}")
                continue
            if 0 <= idx < len(devices):
                logger.info(f"Selected USB device: {devices[idx]}")
                return devices[idx]
            print(f"Invalid selection. Please enter a number between 1 and {len(devices)}")

    return None


def main():
    parser = build_parser()
    args = parser.parse_args()
    configure_logging(args.log_level)

    if args.install:
        install_dependencies()
        return 0

    if args.setup_usb:
        if os.geteuid() != 0:
            print("USB gadget setup requires root privileges. Run with: sudo python3 receiver.py --setup-usb")
            return 1
        if setup_usb_gadget():
            print("USB gadget setup complete!")
            return 0
        print("USB gadget setup failed")
        return 1

    usb_device = pick_usb_device(args.mode, args.usb_device)
    device_name = args.name or os.environ.get("DESKEXTEND_NAME", "RaspberryPi")

    if args.eth_interface:
        interfaces = available_interfaces()
        if interfaces and args.eth_interface not in interfaces:
            logger.error("Interface '%s' not found. Available: %s", args.eth_interface, ", ".join(interfaces))
            return 2
        os.environ["DESKEXTEND_ETH_INTERFACE"] = args.eth_interface
        logger.info("Forced Ethernet interface: %s", args.eth_interface)

    global receiver
    receiver = VideoReceiver(
        mode=args.mode,
        host=args.host,
        port=args.port,
        usb_device=usb_device,
        device_name=device_name
    )

    logger.info(f"Video receiver '{device_name}' starting in {args.mode} mode")
    if args.mode in ["network", "ethernet", "hybrid", "all"]:
        label = "Ethernet" if args.mode == "ethernet" else "Network"
        logger.info(f"  {label}: {args.host}:{args.port}")
        if args.mode in ["network", "ethernet"]:
            allowed = receiver.get_mode_interfaces(args.mode)
            if allowed:
                logger.info("  Allowed interfaces: %s", ", ".join(allowed))
            else:
                logger.warning("  No explicit interfaces detected; default routing rules apply")
    if args.mode in ["usb", "hybrid", "all"]:
        logger.info(f"  USB device: {usb_device or 'auto-detect'}")

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    receiver.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
