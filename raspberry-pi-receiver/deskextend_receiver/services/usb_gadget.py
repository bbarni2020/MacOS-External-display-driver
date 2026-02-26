import os
import subprocess
import time
import logging

logger = logging.getLogger(__name__)

CONFIGFS_MOUNT = "/sys/kernel/config"
GADGET_NAME = "deskextend"
GADGET_DIR = f"{CONFIGFS_MOUNT}/usb_gadget/{GADGET_NAME}"
CONFIG_DIR = f"{GADGET_DIR}/configs/c.1"
FUNC_DIR = f"{GADGET_DIR}/functions/acm.usb0"
STRINGS_DIR = f"{GADGET_DIR}/strings/0x409"
CONFIG_STRINGS_DIR = f"{CONFIG_DIR}/strings/0x409"


def _write(path, value):
    with open(path, "w") as file_handle:
        file_handle.write(f"{value}\n")


def _ensure_configfs():
    if os.path.exists(CONFIGFS_MOUNT):
        return True
    subprocess.run(["modprobe", "configfs"], check=False)
    subprocess.run(["mount", "-t", "configfs", "none", CONFIGFS_MOUNT], check=False)
    return os.path.exists(CONFIGFS_MOUNT)


def _cleanup_existing_gadget():
    if not os.path.isdir(GADGET_DIR):
        return
    try:
        udc_path = os.path.join(GADGET_DIR, "UDC")
        if os.path.exists(udc_path):
            _write(udc_path, "")
        time.sleep(0.2)

        symlink_path = os.path.join(CONFIG_DIR, "acm.usb0")
        if os.path.islink(symlink_path):
            os.unlink(symlink_path)

        for path in [CONFIG_STRINGS_DIR, FUNC_DIR, CONFIG_DIR, STRINGS_DIR, GADGET_DIR]:
            if os.path.isdir(path):
                try:
                    os.rmdir(path)
                except OSError:
                    subprocess.run(["rm", "-rf", path], check=False)
    except Exception as error:
        logger.warning("USB gadget cleanup warning: %s", error)


def _pick_udc(timeout=10.0):
    end_time = time.time() + timeout
    while time.time() < end_time:
        try:
            devices = sorted(os.listdir("/sys/class/udc"))
            if devices:
                return devices[0]
        except Exception:
            pass
        time.sleep(0.2)
    return None


def _wait_for_gadget_tty(timeout=8.0):
    end_time = time.time() + timeout
    while time.time() < end_time:
        if os.path.exists("/dev/ttyGS0"):
            return True
        time.sleep(0.2)
    return False


def setup_usb_gadget():
    if os.geteuid() != 0:
        print("USB gadget setup requires root privileges. Run with: sudo python3 receiver.py --setup-usb")
        return False

    if not _ensure_configfs():
        logger.error("ConfigFS is not available. Ensure CONFIG_USB_GADGET and CONFIG_CONFIGFS_FS are enabled.")
        return False

    try:
        subprocess.run(["modprobe", "libcomposite"], check=False)
        subprocess.run(["modprobe", "dwc2"], check=False)
        subprocess.run(["modprobe", "usb_f_acm"], check=False)
    except Exception:
        pass

    _cleanup_existing_gadget()

    try:
        os.makedirs(GADGET_DIR, exist_ok=True)

        _write(os.path.join(GADGET_DIR, "idVendor"), "0x0525")
        _write(os.path.join(GADGET_DIR, "idProduct"), "0xa4a7")
        _write(os.path.join(GADGET_DIR, "bcdDevice"), "0x0100")
        _write(os.path.join(GADGET_DIR, "bcdUSB"), "0x0200")
        _write(os.path.join(GADGET_DIR, "bDeviceClass"), "0x02")
        _write(os.path.join(GADGET_DIR, "bDeviceSubClass"), "0x00")
        _write(os.path.join(GADGET_DIR, "bDeviceProtocol"), "0x00")

        os.makedirs(STRINGS_DIR, exist_ok=True)
        _write(os.path.join(STRINGS_DIR, "manufacturer"), "DeskExtend")
        _write(os.path.join(STRINGS_DIR, "product"), "DeskExtend Receiver")

        device_serial = os.environ.get("DESKEXTEND_NAME", "RaspberryPi")
        _write(os.path.join(STRINGS_DIR, "serialnumber"), f"DeskExtend-{device_serial}")

        os.makedirs(CONFIG_DIR, exist_ok=True)
        _write(os.path.join(CONFIG_DIR, "MaxPower"), "250")

        os.makedirs(CONFIG_STRINGS_DIR, exist_ok=True)
        _write(os.path.join(CONFIG_STRINGS_DIR, "configuration"), "CDC ACM")

        os.makedirs(FUNC_DIR, exist_ok=True)

        function_link = os.path.join(CONFIG_DIR, "acm.usb0")
        if not os.path.exists(function_link):
            os.symlink(FUNC_DIR, function_link)

        udc_device = _pick_udc(timeout=10.0)
        if not udc_device:
            logger.error("Cannot find USB device controller in /sys/class/udc")
            return False

        _write(os.path.join(GADGET_DIR, "UDC"), udc_device)
        logger.info("USB gadget configured and bound to UDC: %s", udc_device)

        if not _wait_for_gadget_tty(timeout=8.0):
            logger.error("USB gadget configured but /dev/ttyGS0 did not appear")
            return False

        if os.path.exists("/dev/ttyGS0"):
            subprocess.run(["stty", "-F", "/dev/ttyGS0", "115200"], check=False)
            logger.info("Device /dev/ttyGS0 ready")

        return True

    except PermissionError as error:
        logger.error("Permission error: %s", error)
        return False
    except Exception as error:
        logger.error("Error setting up USB gadget: %s", error)
        return False
