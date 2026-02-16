import os
import subprocess
import time
import logging

logger = logging.getLogger(__name__)


def setup_usb_gadget():
    if os.geteuid() != 0:
        print("USB gadget setup requires root privileges. Run with: sudo python3 receiver.py --setup-usb")
        return False

    configfs_mount = "/sys/kernel/config"

    if not os.path.exists(configfs_mount):
        print("ConfigFS not available. Attempting to mount...")
        try:
            subprocess.run(["modprobe", "configfs"], check=False)
            subprocess.run(["mount", "-t", "configfs", "none", configfs_mount], check=False)
        except Exception as e:
            print(f"Error: {e}")

    if not os.path.exists(configfs_mount):
        print("Error: ConfigFS not available and cannot be mounted.")
        print("Your kernel may not have USB gadget support enabled.")
        print("This requires: CONFIG_USB_GADGET=y and CONFIG_CONFIGFS_FS=y in kernel config")
        return False

    try:
        subprocess.run(["modprobe", "libcomposite"], check=False)
        subprocess.run(["modprobe", "usb_f_acm"], check=False)
    except Exception:
        pass

    gadget_dir = "/sys/kernel/config/usb_gadget/deskextend"

    if os.path.isdir(gadget_dir):
        logger.info("Cleaning up existing gadget...")
        try:
            udc_file = os.path.join(gadget_dir, "UDC")
            if os.path.exists(udc_file):
                with open(udc_file, "w") as f:
                    f.write("")
            time.sleep(0.5)

            config_dir = os.path.join(gadget_dir, "configs/c.1")
            if os.path.isdir(config_dir):
                acm_symlink = os.path.join(config_dir, "acm.usb0")
                if os.path.islink(acm_symlink):
                    os.unlink(acm_symlink)

                strings_dir = os.path.join(config_dir, "strings/0x409")
                if os.path.isdir(strings_dir):
                    subprocess.run(["rm", "-rf", strings_dir], check=False)

                subprocess.run(["rmdir", config_dir], check=False)

            func_dir = os.path.join(gadget_dir, "functions/acm.usb0")
            if os.path.isdir(func_dir):
                subprocess.run(["rmdir", func_dir], check=False)

            strings_dir = os.path.join(gadget_dir, "strings/0x409")
            if os.path.isdir(strings_dir):
                subprocess.run(["rm", "-rf", strings_dir], check=False)

            subprocess.run(["rmdir", gadget_dir], check=False)

            time.sleep(0.5)
        except Exception as e:
            logger.warning(f"Cleanup warning: {e}")

    try:
        os.makedirs(gadget_dir, exist_ok=True)

        with open(os.path.join(gadget_dir, "idVendor"), "w") as f:
            f.write("0x1d6b\n")
        with open(os.path.join(gadget_dir, "idProduct"), "w") as f:
            f.write("0x0108\n")

        strings_dir = os.path.join(gadget_dir, "strings/0x409")
        os.makedirs(strings_dir, exist_ok=True)
        with open(os.path.join(strings_dir, "manufacturer"), "w") as f:
            f.write("DeskExtend\n")
        with open(os.path.join(strings_dir, "product"), "w") as f:
            f.write("RaspberryPi\n")

        device_serial = os.environ.get("DESKEXTEND_NAME", "RaspberryPi")
        with open(os.path.join(strings_dir, "serialnumber"), "w") as f:
            f.write(f"DeskExtend-{device_serial}\n")

        config_dir = os.path.join(gadget_dir, "configs/c.1")
        os.makedirs(config_dir, exist_ok=True)
        with open(os.path.join(config_dir, "MaxPower"), "w") as f:
            f.write("500\n")

        func_dir = os.path.join(gadget_dir, "functions/acm.usb0")
        os.makedirs(func_dir, exist_ok=True)

        config_strings = os.path.join(config_dir, "strings/0x409")
        os.makedirs(config_strings, exist_ok=True)
        with open(os.path.join(config_strings, "configuration"), "w") as f:
            f.write("ACM\n")

        symlink_target = os.path.join(config_dir, "acm.usb0")
        if not os.path.exists(symlink_target):
            os.symlink(func_dir, symlink_target)

        try:
            devices = os.listdir("/sys/class/udc")
            if not devices:
                logger.error("No USB device controller found.")
                return False
            udc_device = devices[0]
        except Exception:
            logger.error("Cannot find USB device controller.")
            return False

        with open(os.path.join(gadget_dir, "UDC"), "w") as f:
            f.write(f"{udc_device}\n")

        logger.info(f"USB gadget configured: {udc_device}")

        time.sleep(1)

        if os.path.exists("/dev/ttyGS0"):
            subprocess.run(["stty", "-F", "/dev/ttyGS0", "115200"], check=False)
            logger.info("Device /dev/ttyGS0 ready")

        return True

    except PermissionError as e:
        logger.error(f"Permission error: {e}")
        return False
    except Exception as e:
        logger.error(f"Error setting up USB gadget: {e}")
        return False
