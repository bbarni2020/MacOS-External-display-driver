import subprocess


def install_dependencies():
    print("Installing DeskExtend receiver dependencies...")

    critical_deps = [
        "python3-pip",
        "gstreamer1.0-tools",
        "gstreamer1.0-plugins-base",
        "gstreamer1.0-plugins-good",
        "gstreamer1.0-plugins-bad",
        "gstreamer1.0-libav",
        "libgstreamer1.0-dev"
    ]

    optional_deps = [
        "xrandr",
        "wmctrl",
        "chromium",
        "unclutter"
    ]

    try:
        subprocess.run(["sudo", "apt", "update"], check=True)
    except subprocess.CalledProcessError:
        print("Warning: Failed to update package lists")

    print("\nInstalling critical packages...")
    try:
        subprocess.run(["sudo", "apt", "install", "-y"] + critical_deps, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Warning: Some packages failed to install: {e}")

    print("\nInstalling optional packages (may fail, continuing anyway)...")
    for pkg in optional_deps:
        try:
            subprocess.run(
                ["sudo", "apt", "install", "-y", pkg],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            print(f"  OK {pkg}")
        except subprocess.CalledProcessError:
            print(f"  FAIL {pkg} (not available)")

    pip_deps = ["flask", "python-dotenv", "psutil", "spotipy", "requests", "pyserial"]

    print("\nInstalling Python packages...")
    try:
        subprocess.run(["pip3", "install"] + pip_deps, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Warning: Some Python packages failed to install: {e}")

    print("\nOK Installation complete!")
