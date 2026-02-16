import socket
import struct
import subprocess
import signal
import threading
import time
import os
import logging
import shutil
import pwd
import glob

try:
    import serial
except Exception:
    serial = None

try:
    from flask import Flask, render_template, jsonify, request, redirect
    from dotenv import load_dotenv
    import psutil
except Exception:
    Flask = None
    render_template = None
    jsonify = None
    request = None
    redirect = None
    load_dotenv = None
    psutil = None

from .services.usb_gadget import setup_usb_gadget
from .utils.devices import detect_all_devices, detect_usb_device
from .utils.display import get_screen_resolution, has_vaapi_sink

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


class VideoReceiver:
    def __init__(self, host="0.0.0.0", port=5900, mode="network", usb_device=None, device_name=None):
        self.host = host
        self.port = port
        self.mode = mode
        self.device_name = device_name or os.environ.get("DESKEXTEND_NAME", "RaspberryPi")
        os.environ["DESKEXTEND_NAME"] = self.device_name

        if self.mode in ["usb", "hybrid", "all"]:
            if os.geteuid() == 0:
                logger.info("Setting up USB gadget...")
                setup_usb_gadget()
            else:
                logger.warning("USB mode requires root. USB may not be available.")

        self.usb_device = usb_device or detect_usb_device()
        self.sock = None
        self.serial_conn = None
        self.decoder_process = None
        self.chromium_process = None
        self.unclutter_process = None
        self.kiosk_last_failed = 0.0
        self.running = False
        self.frame_count = 0
        self.last_fps_time = time.time()
        self.current_fps = 0
        self.decoder_type = None
        self.bytes_received = 0
        self.app = None
        self.web_thread = None
        self.startup_flag = {"play": False}
        self.display_connected = False
        self.display_check_thread = None
        self.is_video_streaming = False
        self.serial_idle_timeout = float(os.environ.get("DESKEXTEND_USB_IDLE_TIMEOUT", "5"))

    def get_cpu_temp(self):
        try:
            with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
                temp = int(f.read().strip()) / 1000
            return round(temp, 1)
        except Exception:
            return 0

    def check_display_connected(self):
        try:
            display_env = os.environ.get("DISPLAY", ":0")
            result = subprocess.run(
                ["xrandr", "--query"],
                capture_output=True,
                text=True,
                timeout=2,
                env={**os.environ, "DISPLAY": display_env}
            )
            if result.returncode == 0:
                for line in result.stdout.splitlines():
                    if " connected" in line and "disconnected" not in line:
                        return True

            for status_path in glob.glob("/sys/class/drm/*/status"):
                try:
                    with open(status_path, "r") as f:
                        if f.read().strip().lower() == "connected":
                            return True
                except Exception:
                    continue

            return False
        except Exception as e:
            logger.debug(f"Display check failed: {e}")
            return False

    def display_monitor_loop(self):
        while self.running:
            try:
                connected = self.check_display_connected()
                if connected != self.display_connected:
                    self.display_connected = connected
                    logger.info(
                        f"Display status changed: {'connected' if connected else 'disconnected'}"
                    )
                else:
                    self.display_connected = connected
            except Exception as e:
                logger.warning(f"Display monitor error: {e}")
            time.sleep(60)

    def start_display_monitor(self):
        if not self.display_check_thread or not self.display_check_thread.is_alive():
            self.display_connected = self.check_display_connected()
            logger.info(
                f"Initial display status: {'connected' if self.display_connected else 'disconnected'}"
            )
            self.display_check_thread = threading.Thread(target=self.display_monitor_loop, daemon=True)
            self.display_check_thread.start()

    def start_web_server(self):
        if not Flask or not psutil:
            print("Flask or psutil not available, skipping web server start")
            return
        if self.app:
            print("Web server already running")
            return
        load_dotenv()
        display_mode = os.getenv("DISPLAY_MODE", "dashboard")
        print(f"Display mode: {display_mode}")
        template_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "templates")
        template_dir = os.path.abspath(template_dir)
        self.app = Flask(__name__, template_folder=template_dir)

        @self.app.route("/")
        def dashboard():
            if display_mode == "waiting":
                return render_template("waiting.html")
            return render_template("dashboard.html")

        @self.app.route("/stats")
        def stats():
            if not self.display_connected:
                return {"cpu": 0, "ram": 0, "storage": 0, "temp": 0}
            cpu = psutil.cpu_percent(interval=1)
            ram = psutil.virtual_memory().percent
            storage = psutil.disk_usage("/").percent
            temp = self.get_cpu_temp()
            return {"cpu": round(cpu), "ram": round(ram), "storage": round(storage), "temp": temp}

        @self.app.route("/display-status")
        def display_status():
            return {"connected": self.display_connected}

        @self.app.route("/weather")
        def weather():
            if not self.display_connected:
                return {"temp": "", "desc": "", "icon": ""}
            import requests
            try:
                resp = requests.get("https://wttr.in/?format=j1", timeout=3)
                data = resp.json()
                current = data["current_condition"][0]
                temp = current.get("temp_C")
                desc = current.get("weatherDesc", [{}])[0].get("value", "")
                icon = current.get("weatherIconUrl", [{}])[0].get("value", "")
                return {"temp": temp, "desc": desc, "icon": icon}
            except Exception:
                return {"temp": "", "desc": "", "icon": ""}

        @self.app.route("/spotify")
        def spotify():
            if not self.display_connected:
                return {"authorized": False, "authorize_url": None}
            try:
                import spotipy
                from spotipy.oauth2 import SpotifyOAuth

                client_id = os.getenv("SPOTIPY_CLIENT_ID")
                client_secret = os.getenv("SPOTIPY_CLIENT_SECRET")
                redirect_uri = os.getenv("SPOTIPY_REDIRECT_URI", "http://127.0.0.1:8080/callback")
                cache_path = os.getenv("SPOTIPY_CACHE", ".spotify-token-cache")
                scope = "user-read-currently-playing user-read-playback-state"
                if not (client_id and client_secret):
                    return {"authorized": False, "authorize_url": None}
                auth_manager = SpotifyOAuth(
                    client_id=client_id,
                    client_secret=client_secret,
                    redirect_uri=redirect_uri,
                    scope=scope,
                    cache_path=cache_path,
                    open_browser=False
                )
                token_info = auth_manager.get_cached_token()
                if not token_info:
                    return {"authorized": False, "authorize_url": auth_manager.get_authorize_url()}
                sp = spotipy.Spotify(auth_manager=auth_manager)
                current = sp.current_user_playing_track()
                if not current or not current.get("item"):
                    return {"authorized": True, "title": "", "artist": "", "cover": ""}
                item = current["item"]
                title = item["name"]
                artist = ", ".join([a["name"] for a in item["artists"]])
                cover = item["album"]["images"][0]["url"] if item["album"]["images"] else ""
                return {"authorized": True, "title": title, "artist": artist, "cover": cover}
            except Exception:
                logger.exception("Spotify fetch failed")
                return {"authorized": False, "authorize_url": None}

        @self.app.route("/spotify/login")
        def spotify_login():
            from spotipy.oauth2 import SpotifyOAuth

            client_id = os.getenv("SPOTIPY_CLIENT_ID")
            client_secret = os.getenv("SPOTIPY_CLIENT_SECRET")
            redirect_uri = os.getenv("SPOTIPY_REDIRECT_URI", "http://127.0.0.1:8080/callback")
            cache_path = os.getenv("SPOTIPY_CACHE", ".spotify-token-cache")
            if not (client_id and client_secret):
                return "Spotify credentials not configured", 400
            auth_manager = SpotifyOAuth(
                client_id=client_id,
                client_secret=client_secret,
                redirect_uri=redirect_uri,
                scope="user-read-currently-playing user-read-playback-state",
                cache_path=cache_path
            )
            return redirect(auth_manager.get_authorize_url())

        @self.app.route("/callback")
        def spotify_callback():
            try:
                error = request.args.get("error")
                code = request.args.get("code")
                if error:
                    return render_template("spotify_callback.html", ok=False, error=error)
                if not code:
                    return render_template("spotify_callback.html", ok=False, error="missing code"), 400

                from spotipy.oauth2 import SpotifyOAuth

                client_id = os.getenv("SPOTIPY_CLIENT_ID")
                client_secret = os.getenv("SPOTIPY_CLIENT_SECRET")
                redirect_uri = os.getenv("SPOTIPY_REDIRECT_URI", "http://127.0.0.1:8080/callback")
                cache_path = os.getenv("SPOTIPY_CACHE", ".spotify-token-cache")
                if not (client_id and client_secret):
                    return render_template("spotify_callback.html", ok=False, error="credentials not set"), 400
                auth_manager = SpotifyOAuth(
                    client_id=client_id,
                    client_secret=client_secret,
                    redirect_uri=redirect_uri,
                    scope="user-read-currently-playing user-read-playback-state",
                    cache_path=cache_path
                )
                token_info = auth_manager.get_access_token(code)
                if not token_info:
                    return render_template("spotify_callback.html", ok=False, error="token exchange failed"), 500
                return render_template("spotify_callback.html", ok=True)
            except Exception as e:
                logger.exception("Spotify callback failed")
                return render_template("spotify_callback.html", ok=False, error=str(e)), 500

        @self.app.route("/start", methods=["POST"])
        def start_animation():
            self.startup_flag["play"] = True
            return jsonify({"ok": True})

        @self.app.route("/start-status")
        def start_status():
            if self.startup_flag["play"]:
                self.startup_flag["play"] = False
                return jsonify({"play": True})
            return jsonify({"play": False})

        def run_server():
            self.app.run(host="127.0.0.1", port=8080, debug=False, use_reloader=False)

        self.web_thread = threading.Thread(target=run_server, daemon=True)
        self.web_thread.start()
        self.start_display_monitor()

    def start_chromium_kiosk(self):
        if self.chromium_process and self.chromium_process.poll() is None:
            return True

        if time.time() - self.kiosk_last_failed < 5.0:
            return False

        try:
            self.start_web_server()
        except Exception as e:
            logger.error(f"Failed to start web server: {e}")

        kiosk_url = os.environ.get("KIOSK_URL", "http://127.0.0.1:8080/")

        chromium_bin = os.environ.get("CHROMIUM_BIN")
        if chromium_bin:
            if not shutil.which(chromium_bin):
                logger.error(f"Chromium binary not found: {chromium_bin}")
                self.kiosk_last_failed = time.time()
                return False
        else:
            for candidate in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable"):
                if shutil.which(candidate):
                    chromium_bin = candidate
                    break
            if not chromium_bin:
                logger.error("Chromium not found. Install with: sudo apt install chromium or chromium-browser")
                self.kiosk_last_failed = time.time()
                return False

        if not self.display_connected:
            logger.info("Display not connected - waiting up to 8s for display before launching Chromium")
            for _ in range(16):
                if self.display_connected:
                    break
                time.sleep(0.5)

        env = os.environ.copy()
        if "DISPLAY" not in env:
            env["DISPLAY"] = ":0"
        chromium_args = [
            chromium_bin,
            f"--app={kiosk_url}",
            "--kiosk",
            "--disable-infobars",
            "--no-first-run",
            "--disable-session-crashed-bubble",
            "--start-fullscreen",
            "--window-position=0,0"
        ]

        chromium_user = None
        if os.geteuid() == 0:
            sudo_user = os.environ.get("SUDO_USER")
            if sudo_user:
                chromium_user = sudo_user
            else:
                try:
                    pwd.getpwnam("pi")
                    chromium_user = "pi"
                except KeyError:
                    try:
                        pwd.getpwnam("ubuntu")
                        chromium_user = "ubuntu"
                    except KeyError:
                        pass

        if chromium_user and os.geteuid() == 0:
            try:
                user_info = pwd.getpwnam(chromium_user)
                xauth_file = os.path.join(user_info.pw_dir, ".Xauthority")
                if os.path.exists(xauth_file):
                    env["XAUTHORITY"] = xauth_file
                    env["HOME"] = user_info.pw_dir
            except (KeyError, Exception):
                pass

        if not self.unclutter_process or self.unclutter_process.poll() is not None:
            try:
                try:
                    self.unclutter_process = subprocess.Popen(
                        ["unclutter", "-idle", "0", "-root"],
                        env=env,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                except Exception:
                    self.unclutter_process = None
            except Exception:
                self.unclutter_process = None

        try:
            if chromium_user and os.geteuid() == 0:
                try:
                    pwd.getpwnam(chromium_user)
                    chromium_args = [
                        "runuser", "-u", chromium_user, "--",
                        *chromium_args
                    ]
                except KeyError:
                    logger.warning(f"User {chromium_user} not found, running as root")

            self.chromium_process = subprocess.Popen(
                [*chromium_args],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            logger.info(
                "Chromium kiosk mode started with display (pid=%s)",
                getattr(self.chromium_process, "pid", None)
            )

            time.sleep(1.0)
            try:
                if self.has_wmctrl():
                    if not self.bring_chromium_window(timeout=5.0):
                        logger.info("Chromium started but window not found via wmctrl")
            except Exception:
                pass

            return True
        except Exception as e:
            logger.warning(f"Failed to start chromium: {e}")
            self.kiosk_last_failed = time.time()
            return False

    @staticmethod
    def has_wmctrl():
        try:
            result = subprocess.run(["which", "wmctrl"], capture_output=True, text=True, timeout=1)
            return result.returncode == 0
        except Exception:
            return False

    def bring_chromium_window(self, timeout=5.0):
        if not self.has_wmctrl():
            return False
        end = time.time() + timeout
        candidates = ["Chromium", "chromium", "DeskExtend", "127.0.0.1", "Dashboard"]
        class_candidates = ["chromium.Chromium", "chromium-browser.Chromium", "Chromium.Chromium"]
        while time.time() < end:
            try:
                proc = subprocess.run(["wmctrl", "-l", "-x"], capture_output=True, text=True, timeout=1)
                out = proc.stdout if proc.returncode == 0 else ""
                for line in out.splitlines():
                    parts = line.split()
                    if not parts:
                        continue
                    win_id = parts[0]
                    wm_class = parts[2] if len(parts) > 2 else ""

                    matched = any(pat in line for pat in candidates) or any(
                        cls == wm_class for cls in class_candidates
                    )
                    if not matched:
                        continue
                    try:
                        subprocess.run(["wmctrl", "-i", "-r", win_id, "-b", "remove,hidden"], timeout=1)
                        subprocess.run(["wmctrl", "-i", "-R", win_id], timeout=1)
                        subprocess.run(
                            ["wmctrl", "-i", "-r", win_id, "-b", "add,above,fullscreen"],
                            timeout=1
                        )
                        return True
                    except Exception:
                        continue
            except Exception:
                pass
            time.sleep(0.2)
        return False

    def show_chromium_kiosk(self):
        if self.chromium_process and self.chromium_process.poll() is None:
            try:
                if self.has_wmctrl():
                    self.bring_chromium_window(timeout=5.0)
                else:
                    os.kill(self.chromium_process.pid, signal.SIGCONT)
            except Exception:
                pass
            return

        if not self.start_chromium_kiosk():
            return

    def hide_chromium_kiosk(self):
        if self.chromium_process and self.chromium_process.poll() is None:
            try:
                if self.has_wmctrl():
                    try:
                        proc = subprocess.run(
                            ["wmctrl", "-l"],
                            capture_output=True,
                            text=True,
                            timeout=1,
                            stderr=subprocess.DEVNULL
                        )
                        out = proc.stdout if proc.returncode == 0 else ""
                        for line in out.splitlines():
                            if "Chromium" in line or "chromium" in line:
                                parts = line.split()
                                if parts:
                                    win_id = parts[0]
                                    try:
                                        subprocess.run(
                                            ["wmctrl", "-i", "-r", win_id, "-b", "add,hidden"],
                                            timeout=1,
                                            stderr=subprocess.DEVNULL
                                        )
                                    except Exception:
                                        pass
                    except Exception:
                        pass
                else:
                    try:
                        os.kill(self.chromium_process.pid, signal.SIGSTOP)
                    except Exception:
                        pass
                logger.info("chromium kiosk mode hidden (minimized)")
            except Exception:
                pass

    def hide_chromium_kiosk_delayed(self, delay=5.0):
        try:
            threading.Timer(delay, self.hide_chromium_kiosk).start()
        except Exception as e:
            logger.warning(f"Failed to schedule chromium hide: {e}")

    def stop_chromium_kiosk(self):
        if self.chromium_process:
            try:
                try:
                    self.chromium_process.terminate()
                    try:
                        self.chromium_process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        self.chromium_process.kill()
                except Exception:
                    try:
                        self.chromium_process.kill()
                    except Exception:
                        pass
            except Exception:
                pass
            self.chromium_process = None

        if self.unclutter_process:
            try:
                self.unclutter_process.terminate()
                try:
                    self.unclutter_process.wait(timeout=1)
                except subprocess.TimeoutExpired:
                    self.unclutter_process.kill()
            except Exception:
                pass
            self.unclutter_process = None

    def schedule_hide_when_window_present(self, window_names, appear_timeout=3.0, after_delay=5.0):
        def watcher():
            try:
                end_time = time.time() + appear_timeout
                found = False
                while time.time() < end_time and not found and self.running:
                    try:
                        if self.has_wmctrl():
                            proc = subprocess.run(
                                ["wmctrl", "-l"],
                                capture_output=True,
                                text=True,
                                timeout=1,
                                stderr=subprocess.DEVNULL
                            )
                            out = proc.stdout if proc.returncode == 0 else ""
                        else:
                            proc = subprocess.run(["ps", "aux"], capture_output=True, text=True, timeout=1)
                            out = proc.stdout if proc.returncode == 0 else ""

                        for name in window_names:
                            if name in out:
                                found = True
                                break
                    except Exception:
                        pass
                    if not found:
                        time.sleep(0.25)

                if found and self.running:
                    time.sleep(after_delay)
                    try:
                        self.hide_chromium_kiosk()
                    except Exception:
                        pass
                else:
                    logger.info("No matching window found within timeout; not hiding chromium")
            except Exception as e:
                logger.warning(f"Watcher failed: {e}")

        threading.Thread(target=watcher, daemon=True).start()

    def detect_decoder_pipeline(self):
        pipelines = []

        has_v4l2_sink = os.path.exists("/dev/video0") and os.access("/dev/video0", os.W_OK)
        screen_res = get_screen_resolution()

        if has_vaapi_sink():
            pipelines.append({
                "name": "VAAPI h264 + vaapisink fullscreen",
                "cmd": [
                    "gst-launch-1.0", "-e",
                    "fdsrc", "fd=0",
                    "!", "queue", "max-size-buffers=3", "max-size-time=0", "max-size-bytes=0",
                    "!", "h264parse",
                    "!", "vaapih264dec",
                    "!", "vaapisink", "fullscreen=yes", "sync=false"
                ]
            })

        if screen_res:
            width, height = screen_res
            pipelines.append({
                "name": "Hardware v4l2 + autovideosink (scaled)",
                "cmd": [
                    "gst-launch-1.0", "-e",
                    "fdsrc", "fd=0",
                    "!", "queue", "max-size-buffers=3", "max-size-time=0", "max-size-bytes=0",
                    "!", "h264parse",
                    "!", "v4l2h264dec", "capture-io-mode=mmap",
                    "!", "videoconvert",
                    "!", "videoscale",
                    "!", f"video/x-raw,width={width},height={height}",
                    "!", "autovideosink", "sync=false"
                ]
            })
        else:
            pipelines.append({
                "name": "Hardware v4l2 + autovideosink",
                "cmd": [
                    "gst-launch-1.0", "-e",
                    "fdsrc", "fd=0",
                    "!", "queue", "max-size-buffers=3", "max-size-time=0", "max-size-bytes=0",
                    "!", "h264parse",
                    "!", "v4l2h264dec", "capture-io-mode=mmap",
                    "!", "videoconvert",
                    "!", "autovideosink", "sync=false"
                ]
            })

        if has_v4l2_sink:
            pipelines.append({
                "name": "Hardware MMAL + KMS (/dev/video0)",
                "cmd": [
                    "gst-launch-1.0", "-e",
                    "fdsrc", "fd=0",
                    "!", "queue", "max-size-buffers=2", "max-size-time=0", "max-size-bytes=0",
                    "!", "h264parse",
                    "!", "v4l2h264dec",
                    "!", "v4l2sink", "device=/dev/video0", "sync=false"
                ]
            })

        pipelines.append({
            "name": "Hardware v4l2 + gtksink",
            "cmd": [
                "gst-launch-1.0", "-e",
                "fdsrc", "fd=0",
                "!", "queue", "max-size-buffers=2", "max-size-time=0", "max-size-bytes=0",
                "!", "h264parse",
                "!", "v4l2h264dec",
                "!", "videoconvert",
                "!", "gtksink", "fullscreen=true", "sync=false"
            ]
        })

        if screen_res:
            width, height = screen_res
            pipelines.append({
                "name": "Software avdec + autovideosink (scaled)",
                "cmd": [
                    "gst-launch-1.0", "-e",
                    "fdsrc", "fd=0",
                    "!", "queue", "max-size-buffers=4", "max-size-time=0", "max-size-bytes=0",
                    "!", "h264parse",
                    "!", "avdec_h264", "max-threads=4",
                    "!", "videoconvert",
                    "!", "videoscale",
                    "!", f"video/x-raw,width={width},height={height}",
                    "!", "autovideosink", "sync=false"
                ]
            })
        else:
            pipelines.append({
                "name": "Software avdec + autovideosink",
                "cmd": [
                    "gst-launch-1.0", "-e",
                    "fdsrc", "fd=0",
                    "!", "queue", "max-size-buffers=4", "max-size-time=0", "max-size-bytes=0",
                    "!", "h264parse",
                    "!", "avdec_h264", "max-threads=4",
                    "!", "videoconvert",
                    "!", "autovideosink", "sync=false"
                ]
            })

        return pipelines

    def start_decoder(self):
        pipelines = self.detect_decoder_pipeline()

        print(f"DISPLAY environment: {os.environ.get('DISPLAY', 'NOT SET')}")

        for pipeline_info in pipelines:
            try:
                pipeline = pipeline_info["cmd"]
                logger.info(f"Trying: {pipeline_info['name']}")

                env = os.environ.copy()
                if "DISPLAY" not in env:
                    env["DISPLAY"] = ":0"

                self.decoder_process = subprocess.Popen(
                    pipeline,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    env=env,
                    bufsize=0
                )

                time.sleep(1.0)

                if self.decoder_process.poll() is None:
                    self.decoder_type = pipeline_info["name"]
                    logger.info(f"Decoder started: {self.decoder_type}")
                    self.apply_wmctrl_fullscreen()
                    threading.Thread(target=self.monitor_decoder_errors, daemon=True).start()
                    return True
                try:
                    stderr = self.decoder_process.stderr.read().decode("utf-8", errors="ignore")
                    logger.warning(f"Failed: {stderr[:200]}")
                except Exception:
                    pass
            except Exception as e:
                logger.warning(f"Error: {e}")
                continue

        logger.error("All decoder pipelines failed")
        return False

    def apply_wmctrl_fullscreen(self):
        if not self.has_wmctrl():
            return

        window_names = [
            "vaapisink",
            "autovideosink",
            "gst-launch-1.0"
        ]

        def worker(delay=5.0):
            try:
                time.sleep(delay)
                for name in window_names:
                    try:
                        subprocess.run(
                            ["wmctrl", "-r", name, "-b", "add,fullscreen,above"],
                            timeout=1,
                            stderr=subprocess.DEVNULL
                        )
                    except Exception:
                        continue
            except Exception:
                return

        threading.Thread(target=worker, daemon=True).start()

    def monitor_decoder_errors(self):
        if not self.decoder_process or not self.decoder_process.stderr:
            return

        while self.running and self.decoder_process:
            try:
                line = self.decoder_process.stderr.readline()
                if not line:
                    break

                line = line.decode("utf-8", errors="ignore").strip()
                if line and ("ERROR" in line or "WARN" in line):
                    logger.warning(f"GStreamer: {line}")
            except Exception:
                break

    def bind_socket(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.sock.bind((self.host, self.port))
            self.sock.listen(1)
            self.sock.settimeout(5.0)
            logger.info(f"[{self.device_name}] Listening on {self.host}:{self.port}")
            return True
        except Exception as e:
            logger.error(f"Socket bind failed: {e}")
            return False

    def open_usb(self):
        if not self.usb_device:
            logger.error("No USB device detected")
            return False

        try:
            try:
                from serial import Serial as _Serial, SerialException as _SerialException
            except Exception:
                if serial and hasattr(serial, "Serial"):
                    _Serial = serial.Serial
                    _SerialException = getattr(serial, "SerialException", Exception)
                else:
                    logger.error("pyserial not available or invalid 'serial' module")
                    return False

            self.serial_conn = _Serial(
                port=self.usb_device,
                baudrate=115200,
                timeout=1.0,
                write_timeout=1.0
            )
            logger.info(f"Opened USB device: {self.usb_device}")
            return True
        except Exception as e:
            logger.error(f"Failed to open USB device: {e}")
            return False

    def close_usb(self):
        if self.serial_conn:
            try:
                self.serial_conn.close()
            except Exception:
                pass
            self.serial_conn = None

    def update_fps(self):
        self.frame_count += 1
        now = time.time()
        elapsed = now - self.last_fps_time
        if elapsed >= 1.0:
            self.current_fps = self.frame_count / elapsed
            mbps = (self.bytes_received * 8) / (elapsed * 1_000_000)
            logger.info(
                f"FPS: {self.current_fps:.1f} | Bitrate: {mbps:.1f} Mbps | Frames: {self.frame_count}"
            )
            self.frame_count = 0
            self.bytes_received = 0
            self.last_fps_time = now

    def read_from_connection(self, conn, chunk_size=262144):
        try:
            if serial and hasattr(serial, "Serial") and isinstance(conn, serial.Serial):
                return conn.read(min(chunk_size, 4096)) if conn.in_waiting else b""
            return conn.recv(chunk_size)
        except socket.timeout:
            return b""
        except Exception as e:
            if serial and hasattr(serial, "SerialException") and isinstance(e, serial.SerialException):
                return None
            logger.error(f"Read error: {e}")
            return None

    def process_stream(self, conn):
        logger.info("Processing video stream...")
        self.hide_chromium_kiosk()
        self.is_video_streaming = True

        buffer = b""
        is_serial = serial and hasattr(serial, "Serial") and isinstance(conn, serial.Serial)
        last_data_time = time.time()

        try:
            while self.running:
                try:
                    chunk = self.read_from_connection(conn)
                    if chunk is None:
                        break
                    if not chunk:
                        if is_serial:
                            if time.time() - last_data_time > self.serial_idle_timeout:
                                logger.info("USB stream idle, reconnecting...")
                                return False
                            time.sleep(0.001)
                        continue
                    if is_serial:
                        last_data_time = time.time()

                    buffer += chunk
                    self.bytes_received += len(chunk)

                    while len(buffer) >= 4:
                        frame_size = struct.unpack(">I", buffer[:4]
                        )[0]

                        if frame_size > 10485760:
                            logger.warning(f"Invalid frame size: {frame_size}")
                            buffer = buffer[1:]
                            continue

                        if len(buffer) < 4 + frame_size:
                            break

                        frame_data = buffer[4:4 + frame_size]
                        buffer = buffer[4 + frame_size:]

                        if self.decoder_process and self.decoder_process.stdin:
                            try:
                                self.decoder_process.stdin.write(frame_data)
                                self.decoder_process.stdin.flush()
                                self.update_fps()
                            except BrokenPipeError:
                                logger.error("Decoder pipe broken - restarting...")
                                self.is_video_streaming = False
                                self.show_chromium_kiosk()
                                return False
                            except Exception as e:
                                logger.error(f"Decoder write error: {e}")
                                self.is_video_streaming = False
                                self.show_chromium_kiosk()
                                return False

                except socket.error as e:
                    logger.error(f"Socket error: {e}")
                    break
                except Exception as e:
                    logger.error(f"Stream error: {e}")
                    break
        finally:
            self.is_video_streaming = False
            self.show_chromium_kiosk()

        return True

    def run_usb(self):
        self.running = True

        logger.info(f"Starting USB mode on device: {self.usb_device}")
        retry_delay = 1.0
        max_retry_delay = 15.0

        self.show_chromium_kiosk()

        while self.running:
            try:
                if not self.display_connected:
                    time.sleep(1)
                    continue

                if self.usb_device and not os.path.exists(self.usb_device):
                    self.usb_device = None

                if self.usb_device:
                    opened = self.open_usb()
                    if not opened:
                        opened = False
                        for dev in detect_all_devices():
                            self.usb_device = dev
                            if self.open_usb():
                                opened = True
                                break
                        if not opened:
                            logger.warning("Retrying USB connection in 3 seconds...")
                            time.sleep(retry_delay)
                            retry_delay = min(max_retry_delay, retry_delay * 1.5)
                            continue
                else:
                    opened = False
                    for dev in detect_all_devices():
                        self.usb_device = dev
                        if self.open_usb():
                            opened = True
                            break
                    if not opened:
                        logger.warning("No USB device found, retrying in 3 seconds...")
                        time.sleep(retry_delay)
                        retry_delay = min(max_retry_delay, retry_delay * 1.5)
                        continue

                self.schedule_hide_when_window_present(
                    ["vaapisink", "autovideosink", "gst-launch-1.0"],
                    appear_timeout=3.0,
                    after_delay=5.0
                )

                if not self.start_decoder():
                    self.close_usb()
                    self.show_chromium_kiosk()
                    time.sleep(retry_delay)
                    retry_delay = min(max_retry_delay, retry_delay * 1.5)
                    continue

                logger.info(f"[{self.device_name}] USB connection established")
                retry_delay = 1.0
                self.frame_count = 0
                self.bytes_received = 0
                self.last_fps_time = time.time()

                self.process_stream(self.serial_conn)

                self.close_usb()

                if self.decoder_process:
                    self.decoder_process.terminate()
                    try:
                        self.decoder_process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        self.decoder_process.kill()
                    self.decoder_process = None

                logger.info("USB connection closed, waiting for next connection...")
                self.show_chromium_kiosk()
                time.sleep(1)

            except Exception as e:
                if self.running:
                    logger.error(f"USB error: {e}")
                    self.close_usb()
                    self.show_chromium_kiosk()
                    time.sleep(retry_delay)
                    retry_delay = min(max_retry_delay, retry_delay * 1.5)

    def run_hybrid(self):
        self.running = True

        logger.info("Starting hybrid mode (USB priority with network fallback)")
        retry_delay = 1.0
        max_retry_delay = 15.0
        usb_scan_delay = 1.0
        max_usb_scan_delay = 15.0
        next_usb_scan = 0.0

        self.show_chromium_kiosk()

        usb_active = False

        while self.running:
            try:
                if not self.display_connected:
                    time.sleep(1)
                    continue

                if self.usb_device and not os.path.exists(self.usb_device):
                    self.usb_device = None

                if not self.usb_device and time.time() >= next_usb_scan:
                    detected = detect_usb_device()
                    if detected:
                        self.usb_device = detected
                        usb_scan_delay = 1.0
                    else:
                        usb_scan_delay = min(max_usb_scan_delay, usb_scan_delay * 1.5)
                    next_usb_scan = time.time() + usb_scan_delay

                if self.usb_device and not usb_active:
                    logger.info(f"Attempting USB connection: {self.usb_device}")
                    if not self.open_usb():
                        opened = False
                        for dev in detect_all_devices():
                            self.usb_device = dev
                            if self.open_usb():
                                opened = True
                                break
                        if not opened:
                            logger.warning("USB connection failed, falling back to network...")
                            self.usb_device = None
                            next_usb_scan = time.time() + usb_scan_delay
                            retry_delay = min(max_retry_delay, retry_delay * 1.5)
                        else:
                            usb_active = True
                    else:
                        usb_active = True
                        retry_delay = 1.0

                    if usb_active:
                        self.schedule_hide_when_window_present(
                            ["vaapisink", "autovideosink", "gst-launch-1.0"],
                            appear_timeout=3.0,
                            after_delay=5.0
                        )
                        if not self.start_decoder():
                            self.close_usb()
                            usb_active = False
                            self.show_chromium_kiosk()
                            retry_delay = min(max_retry_delay, retry_delay * 1.5)
                        else:
                            logger.info("USB connected, processing stream...")
                            retry_delay = 1.0
                            self.frame_count = 0
                            self.bytes_received = 0
                            self.last_fps_time = time.time()
                            self.process_stream(self.serial_conn)
                            self.close_usb()
                            usb_active = False
                            if self.decoder_process:
                                self.decoder_process.terminate()
                                try:
                                    self.decoder_process.wait(timeout=3)
                                except subprocess.TimeoutExpired:
                                    self.decoder_process.kill()
                                self.decoder_process = None
                            logger.info("USB connection closed")
                            self.show_chromium_kiosk()
                            time.sleep(1)
                            continue

                logger.info(f"[{self.device_name}] Listening on network {self.host}:{self.port}")
                if not self.bind_socket():
                    time.sleep(retry_delay)
                    retry_delay = min(max_retry_delay, retry_delay * 1.5)

                logger.info(f"[{self.device_name}] Waiting for network connection...")
                self.sock.settimeout(2.0)

                try:
                    conn, addr = self.sock.accept()
                    logger.info(f"[{self.device_name}] Connected from {addr}")

                    self.schedule_hide_when_window_present(
                        ["vaapisink", "autovideosink", "gst-launch-1.0"],
                        appear_timeout=3.0,
                        after_delay=5.0
                    )

                    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)

                    if not self.start_decoder():
                        conn.close()
                        self.sock.close()
                        self.show_chromium_kiosk()
                        continue

                    self.frame_count = 0
                    self.bytes_received = 0
                    self.last_fps_time = time.time()

                    self.process_stream(conn)

                    conn.close()

                    if self.decoder_process:
                        self.decoder_process.terminate()
                        try:
                            self.decoder_process.wait(timeout=3)
                        except subprocess.TimeoutExpired:
                            self.decoder_process.kill()
                        self.decoder_process = None

                    self.sock.close()
                    logger.info("Network connection closed")
                    self.show_chromium_kiosk()

                except socket.timeout:
                    if self.usb_device:
                        logger.info("No network connection, retrying USB...")

            except Exception as e:
                if self.running:
                    logger.error(f"Hybrid mode error: {e}")
                    if self.sock:
                        self.sock.close()
                    self.close_usb()
                    self.show_chromium_kiosk()
                    time.sleep(retry_delay)
                    retry_delay = min(max_retry_delay, retry_delay * 1.5)

    def run(self):
        self.running = True

        if self.mode == "usb":
            self.run_usb()
        elif self.mode == "hybrid":
            self.run_hybrid()
        elif self.mode == "all":
            self.run_all()
        else:
            self.run_network()

    def run_all(self):
        self.running = True
        logger.info("Starting all modes (USB + Network)")
        self.show_chromium_kiosk()

        usb_thread = threading.Thread(target=self.run_usb, daemon=True)
        network_thread = threading.Thread(target=self.run_network, daemon=True)

        usb_thread.start()
        network_thread.start()

        usb_thread.join()
        network_thread.join()

    def run_network(self):
        self.running = True

        if not self.bind_socket():
            return

        logger.info("Waiting for network connection...")

        self.show_chromium_kiosk()

        while self.running:
            try:
                if not self.display_connected:
                    time.sleep(1)
                    continue

                conn, addr = self.sock.accept()
                logger.info(f"[{self.device_name}] Connected from {addr}")

                self.schedule_hide_when_window_present(
                    ["vaapisink", "autovideosink", "gst-launch-1.0"],
                    appear_timeout=3.0,
                    after_delay=5.0
                )

                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)

                if not self.start_decoder():
                    conn.close()
                    self.show_chromium_kiosk()
                    continue

                self.frame_count = 0
                self.bytes_received = 0
                self.last_fps_time = time.time()

                self.process_stream(conn)

                conn.close()

                if self.decoder_process:
                    self.decoder_process.terminate()
                    try:
                        self.decoder_process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        self.decoder_process.kill()
                    self.decoder_process = None

                logger.info("Network connection closed, waiting for next connection...")
                self.show_chromium_kiosk()

            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    logger.error(f"Connection error: {e}")
                    self.show_chromium_kiosk()
                    time.sleep(1)

    def stop(self):
        self.running = False

        if self.decoder_process:
            self.decoder_process.terminate()
            try:
                self.decoder_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.decoder_process.kill()

        self.stop_chromium_kiosk()

        if self.sock:
            self.sock.close()

        logger.info("Receiver stopped")
