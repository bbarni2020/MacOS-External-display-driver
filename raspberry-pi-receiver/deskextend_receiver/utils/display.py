import os
import subprocess
import logging

logger = logging.getLogger(__name__)


def get_screen_resolution():
    try:
        result = subprocess.run(
            r"xrandr | grep '\*' | tr -s ' ' | cut -d' ' -f2",
            shell=True,
            capture_output=True,
            text=True,
            timeout=2
        )
        if result.returncode == 0 and result.stdout.strip():
            resolution = result.stdout.strip().split("\n")[0]
            if "x" in resolution:
                width, height = resolution.split("x")
                return int(width), int(height)
    except Exception as e:
        logger.warning(f"Failed to get screen resolution: {e}")
    return None


def has_vaapi_sink():
    try:
        result = subprocess.run(
            ["gst-inspect-1.0", "vaapisink"],
            capture_output=True,
            text=True,
            timeout=2
        )
        return result.returncode == 0
    except Exception:
        return False
