from .core import VideoReceiver
from .services.deps import install_dependencies
from .services.usb_gadget import setup_usb_gadget

__all__ = ["VideoReceiver", "install_dependencies", "setup_usb_gadget"]
