#!/usr/bin/env python3

import socket
import struct
import subprocess
import signal
import sys
import threading
import time
import os
import logging
try:
    import serial
except Exception:
    serial = None
import glob
try:
    from flask import Flask, render_template
    from dotenv import load_dotenv
    import psutil
except Exception:
    Flask = None
    render_template = None
    load_dotenv = None
    psutil = None

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

def get_waiting_html_path():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(script_dir, 'waiting.html')

class VideoReceiver:
    def __init__(self, host='0.0.0.0', port=5900, mode='network', usb_device=None):
        self.host = host
        self.port = port
        self.mode = mode
        self.usb_device = usb_device or self.detect_usb_device()
        self.sock = None
        self.serial_conn = None
        self.decoder_process = None
        self.firefox_process = None
        self.running = False
        self.frame_count = 0
        self.last_fps_time = time.time()
        self.current_fps = 0
        self.decoder_type = None
        self.bytes_received = 0
        self.app = None
        self.web_thread = None
    
    def get_cpu_temp(self):
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp = int(f.read().strip()) / 1000
            return round(temp, 1)
        except:
            return 0
    
    def start_web_server(self):
        if not Flask or not psutil:
            return
        if self.app:
            return
        load_dotenv()
        display_mode = os.getenv('DISPLAY_MODE', 'dashboard')
        template_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'templates')
        self.app = Flask(__name__, template_folder=template_dir)
        
        @self.app.route('/')
        def dashboard():
            if display_mode == 'waiting':
                return render_template('waiting.html')
            else:
                return render_template('dashboard.html')
        
        @self.app.route('/stats')
        def stats():
            cpu = psutil.cpu_percent(interval=1)
            ram = psutil.virtual_memory().percent
            storage = psutil.disk_usage('/').percent
            temp = self.get_cpu_temp()
            return {'cpu': round(cpu), 'ram': round(ram), 'storage': round(storage), 'temp': temp}
        
        def run_server():
            self.app.run(host='127.0.0.1', port=8080, debug=False, use_reloader=False)
        
        self.web_thread = threading.Thread(target=run_server, daemon=True)
        self.web_thread.start()
        patterns = ['/dev/ttyUSB*', '/dev/ttyACM*', '/dev/cu.usbmodem*']
        for pattern in patterns:
            devices = glob.glob(pattern)
            if devices:
                return devices[0]
        return None
    
    @staticmethod
    def detect_all_devices():
        devices = []
        patterns = ['/dev/ttyUSB*', '/dev/ttyACM*', '/dev/cu.usbmodem*']
        for pattern in patterns:
            devices.extend(glob.glob(pattern))
        return devices
    
    def start_firefox_kiosk(self):
        if self.firefox_process and self.firefox_process.poll() is None:
            return True

        self.start_web_server()
        
        try:
            env = os.environ.copy()
            if 'DISPLAY' not in env:
                env['DISPLAY'] = ':0'
            
            self.firefox_process = subprocess.Popen(
                ['firefox', '--kiosk', 'http://127.0.0.1:8080/'],
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            logger.info("Firefox kiosk mode started with display")
            return True
        except Exception as e:
            logger.warning(f"Failed to start Firefox: {e}")
            return False
    
    @staticmethod
    def has_wmctrl():
        try:
            result = subprocess.run(['which', 'wmctrl'], capture_output=True, text=True, timeout=1)
            return result.returncode == 0
        except Exception:
            return False

    def show_firefox_kiosk(self):
        if not self.start_firefox_kiosk():
            return

    def hide_firefox_kiosk(self):
        if self.firefox_process and self.firefox_process.poll() is None:
            try:
                if self.has_wmctrl():
                    try:
                        proc = subprocess.run(['wmctrl', '-l'], capture_output=True, text=True, timeout=1)
                        out = proc.stdout if proc.returncode == 0 else ''
                        for line in out.splitlines():
                            if 'Firefox' in line or 'firefox' in line:
                                parts = line.split()
                                if parts:
                                    win_id = parts[0]
                                    try:
                                        subprocess.run(['wmctrl', '-i', '-r', win_id, '-b', 'add,hidden'], timeout=1)
                                    except Exception:
                                        pass
                    except Exception:
                        pass
                else:
                    try:
                        os.kill(self.firefox_process.pid, signal.SIGSTOP)
                    except Exception:
                        pass
                logger.info("Firefox kiosk mode hidden (minimized)")
            except Exception:
                pass

    def hide_firefox_kiosk_delayed(self, delay=5.0):
        try:
            threading.Timer(delay, self.hide_firefox_kiosk).start()
        except Exception as e:
            logger.warning(f"Failed to schedule Firefox hide: {e}")

    def stop_firefox_kiosk(self):
        if self.firefox_process:
            try:
                try:
                    self.firefox_process.terminate()
                    try:
                        self.firefox_proce
                        ss.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        self.firefox_process.kill()
                except Exception:
                    try:
                        self.firefox_process.kill()
                    except Exception:
                        pass
            except Exception:
                pass
            self.firefox_process = None

    def schedule_hide_when_window_present(self, window_names, appear_timeout=3.0, after_delay=5.0):
        def watcher():
            try:
                end_time = time.time() + appear_timeout
                found = False
                while time.time() < end_time and not found and self.running:
                    try:
                        if self.has_wmctrl():
                            proc = subprocess.run(['wmctrl', '-l'], capture_output=True, text=True, timeout=1)
                            out = proc.stdout if proc.returncode == 0 else ''
                        else:
                            proc = subprocess.run(['ps', 'aux'], capture_output=True, text=True, timeout=1)
                            out = proc.stdout if proc.returncode == 0 else ''

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
                        self.hide_firefox_kiosk()
                    except Exception:
                        pass
                else:
                    logger.info("No matching window found within timeout; not hiding Firefox")
            except Exception as e:
                logger.warning(f"Watcher failed: {e}")

        threading.Thread(target=watcher, daemon=True).start()
    
    @staticmethod
    def get_screen_resolution():
        try:
            result = subprocess.run(
                "xrandr | grep '\*' | tr -s ' ' | cut -d' ' -f2",
                shell=True,
                capture_output=True,
                text=True,
                timeout=2
            )
            if result.returncode == 0 and result.stdout.strip():
                resolution = result.stdout.strip().split('\n')[0]
                if 'x' in resolution:
                    width, height = resolution.split('x')
                    return int(width), int(height)
        except Exception as e:
            logger.warning(f"Failed to get screen resolution: {e}")
        return None

    @staticmethod
    def has_vaapi_sink():
        try:
            result = subprocess.run(
                ['gst-inspect-1.0', 'vaapisink'],
                capture_output=True,
                text=True,
                timeout=2
            )
            return result.returncode == 0
        except Exception:
            return False
    
    def detect_decoder_pipeline(self):
        pipelines = []

        has_v4l2_sink = os.path.exists('/dev/video0') and os.access('/dev/video0', os.W_OK)
        screen_res = self.get_screen_resolution()

        if self.has_vaapi_sink():
            pipelines.append({
                'name': 'VAAPI h264 + vaapisink fullscreen',
                'cmd': [
                    'gst-launch-1.0', '-e',
                    'fdsrc', 'fd=0',
                    '!', 'queue', 'max-size-buffers=3', 'max-size-time=0', 'max-size-bytes=0',
                    '!', 'h264parse',
                    '!', 'vaapih264dec',
                    '!', 'vaapisink', 'fullscreen=yes', 'sync=false'
                ]
            })

        if screen_res:
            width, height = screen_res
            pipelines.append({
                'name': 'Hardware v4l2 + autovideosink (scaled)',
                'cmd': [
                    'gst-launch-1.0', '-e',
                    'fdsrc', 'fd=0',
                    '!', 'queue', 'max-size-buffers=3', 'max-size-time=0', 'max-size-bytes=0',
                    '!', 'h264parse',
                    '!', 'v4l2h264dec', 'capture-io-mode=mmap',
                    '!', 'videoconvert',
                    '!', 'videoscale',
                    '!', f'video/x-raw,width={width},height={height}',
                    '!', 'autovideosink', 'sync=false'
                ]
            })
        else:
            pipelines.append({
                'name': 'Hardware v4l2 + autovideosink',
                'cmd': [
                    'gst-launch-1.0', '-e',
                    'fdsrc', 'fd=0',
                    '!', 'queue', 'max-size-buffers=3', 'max-size-time=0', 'max-size-bytes=0',
                    '!', 'h264parse',
                    '!', 'v4l2h264dec', 'capture-io-mode=mmap',
                    '!', 'videoconvert',
                    '!', 'autovideosink', 'sync=false'
                ]
            })

        if has_v4l2_sink:
            pipelines.append({
                'name': 'Hardware MMAL + KMS (/dev/video0)',
                'cmd': [
                    'gst-launch-1.0', '-e',
                    'fdsrc', 'fd=0',
                    '!', 'queue', 'max-size-buffers=2', 'max-size-time=0', 'max-size-bytes=0',
                    '!', 'h264parse',
                    '!', 'v4l2h264dec',
                    '!', 'v4l2sink', 'device=/dev/video0', 'sync=false'
                ]
            })

        pipelines.append({
            'name': 'Hardware v4l2 + gtksink',
            'cmd': [
                'gst-launch-1.0', '-e',
                'fdsrc', 'fd=0',
                '!', 'queue', 'max-size-buffers=2', 'max-size-time=0', 'max-size-bytes=0',
                '!', 'h264parse',
                '!', 'v4l2h264dec',
                '!', 'videoconvert',
                '!', 'gtksink', 'fullscreen=true', 'sync=false'
            ]
        })

        if screen_res:
            width, height = screen_res
            pipelines.append({
                'name': 'Software avdec + autovideosink (scaled)',
                'cmd': [
                    'gst-launch-1.0', '-e',
                    'fdsrc', 'fd=0',
                    '!', 'queue', 'max-size-buffers=4', 'max-size-time=0', 'max-size-bytes=0',
                    '!', 'h264parse',
                    '!', 'avdec_h264', 'max-threads=4',
                    '!', 'videoconvert',
                    '!', 'videoscale',
                    '!', f'video/x-raw,width={width},height={height}',
                    '!', 'autovideosink', 'sync=false'
                ]
            })
        else:
            pipelines.append({
                'name': 'Software avdec + autovideosink',
                'cmd': [
                    'gst-launch-1.0', '-e',
                    'fdsrc', 'fd=0',
                    '!', 'queue', 'max-size-buffers=4', 'max-size-time=0', 'max-size-bytes=0',
                    '!', 'h264parse',
                    '!', 'avdec_h264', 'max-threads=4',
                    '!', 'videoconvert',
                    '!', 'autovideosink', 'sync=false'
                ]
            })

        return pipelines
    
    def start_decoder(self):
        pipelines = self.detect_decoder_pipeline()
        
        print(f"DISPLAY environment: {os.environ.get('DISPLAY', 'NOT SET')}")
        
        for pipeline_info in pipelines:
            try:
                pipeline = pipeline_info['cmd']
                logger.info(f"Trying: {pipeline_info['name']}")
                
                env = os.environ.copy()
                if 'DISPLAY' not in env:
                    env['DISPLAY'] = ':0'
                
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
                    self.decoder_type = pipeline_info['name']
                    logger.info(f"Decoder started: {self.decoder_type}")
                    self.apply_wmctrl_fullscreen()
                    threading.Thread(target=self.monitor_decoder_errors, daemon=True).start()
                    return True
                else:
                    try:
                        stderr = self.decoder_process.stderr.read().decode('utf-8', errors='ignore')
                        logger.warning(f"Failed: {stderr[:200]}")
                    except:
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
            'vaapisink',
            'autovideosink',
            'gst-launch-1.0'
        ]

        def worker(delay=5.0):
            try:
                time.sleep(delay)
                for name in window_names:
                    try:
                        subprocess.run(['wmctrl', '-r', name, '-b', 'toggle,fullscreen'], timeout=1)
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
                
                line = line.decode('utf-8', errors='ignore').strip()
                if line and ('ERROR' in line or 'WARN' in line):
                    logger.warning(f"GStreamer: {line}")
            except:
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
            logger.info(f"Listening on {self.host}:{self.port}")
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
                if serial and hasattr(serial, 'Serial'):
                    _Serial = serial.Serial
                    _SerialException = getattr(serial, 'SerialException', Exception)
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
            except:
                pass
            self.serial_conn = None
    
    def update_fps(self):
        self.frame_count += 1
        now = time.time()
        elapsed = now - self.last_fps_time
        if elapsed >= 1.0:
            self.current_fps = self.frame_count / elapsed
            mbps = (self.bytes_received * 8) / (elapsed * 1_000_000)
            logger.info(f"FPS: {self.current_fps:.1f} | Bitrate: {mbps:.1f} Mbps | Frames: {self.frame_count}")
            self.frame_count = 0
            self.bytes_received = 0
            self.last_fps_time = now
    
    def read_from_connection(self, conn, chunk_size=262144):
        try:
            if serial and hasattr(serial, 'Serial') and isinstance(conn, serial.Serial):
                return conn.read(min(chunk_size, 4096)) if conn.in_waiting else b''
            else:
                return conn.recv(chunk_size)
        except socket.timeout:
            return b''
        except Exception as e:
            if serial and hasattr(serial, 'SerialException') and isinstance(e, serial.SerialException):
                return b''
            logger.error(f"Read error: {e}")
            return None
    
    def process_stream(self, conn):
        logger.info("Processing video stream...")
        
        buffer = b''
        is_serial = serial and hasattr(serial, 'Serial') and isinstance(conn, serial.Serial)
        
        while self.running:
            try:
                chunk = self.read_from_connection(conn)
                if chunk is None:
                    break
                if not chunk:
                    if is_serial:
                        import time
                        time.sleep(0.001)
                    continue
                
                buffer += chunk
                self.bytes_received += len(chunk)
                
                while len(buffer) >= 4:
                    frame_size = struct.unpack('>I', buffer[:4])[0]
                    
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
                            return False
                        except Exception as e:
                            logger.error(f"Decoder write error: {e}")
                            return False
                    
            except socket.error as e:
                logger.error(f"Socket error: {e}")
                break
            except Exception as e:
                logger.error(f"Stream error: {e}")
                break
        
        return True
    
    
    def run_usb(self):
        self.running = True
        
        logger.info(f"Starting USB mode on device: {self.usb_device}")
        
        self.show_firefox_kiosk()
        
        while self.running:
            try:
                if not self.open_usb():
                    logger.warning("Retrying USB connection in 3 seconds...")
                    time.sleep(3)
                    continue
                self.schedule_hide_when_window_present(['vaapisink', 'autovideosink', 'gst-launch-1.0'], appear_timeout=3.0, after_delay=5.0)
                
                if not self.start_decoder():
                    self.close_usb()
                    self.show_firefox_kiosk()
                    time.sleep(3)
                    continue
                
                logger.info("USB connection established")
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
                self.show_firefox_kiosk()
                time.sleep(1)
                
            except Exception as e:
                if self.running:
                    logger.error(f"USB error: {e}")
                    self.close_usb()
                    self.show_firefox_kiosk()
                    time.sleep(3)
    
    def run_hybrid(self):
        self.running = True
        
        logger.info("Starting hybrid mode (USB priority with network fallback)")
        
        self.show_firefox_kiosk()
        
        network_thread = None
        usb_active = False
        
        while self.running:
            try:
                if self.usb_device and not usb_active:
                    logger.info(f"Attempting USB connection: {self.usb_device}")
                    if self.open_usb():
                        usb_active = True
                        self.schedule_hide_when_window_present(['vaapisink', 'autovideosink', 'gst-launch-1.0'], appear_timeout=3.0, after_delay=5.0)
                        
                        if not self.start_decoder():
                            self.close_usb()
                            usb_active = False
                            self.show_firefox_kiosk()
                        else:
                            logger.info("USB connected, processing stream...")
                            self.frame_count = 0
                            self.bytes_received = 0
                            self.last_fps_time = time.time()
                            
                            usb_success = self.process_stream(self.serial_conn)
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
                            self.show_firefox_kiosk()
                            time.sleep(1)
                            continue
                    else:
                        logger.warning("USB connection failed, falling back to network...")
                
                logger.info(f"Listening on network {self.host}:{self.port}")
                if not self.bind_socket():
                    time.sleep(3)
                
                logger.info("Waiting for network connection...")
                self.sock.settimeout(2.0)
                
                try:
                    conn, addr = self.sock.accept()
                    logger.info(f"Connected from {addr}")
                    
                    self.schedule_hide_when_window_present(['vaapisink', 'autovideosink', 'gst-launch-1.0'], appear_timeout=3.0, after_delay=5.0)
                    
                    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
                    
                    if not self.start_decoder():
                        conn.close()
                        self.sock.close()
                        self.show_firefox_kiosk()
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
                    self.show_firefox_kiosk()
                    
                except socket.timeout:
                    if self.usb_device:
                        logger.info("No network connection, retrying USB...")
                    
            except Exception as e:
                if self.running:
                    logger.error(f"Hybrid mode error: {e}")
                    if self.sock:
                        self.sock.close()
                    self.close_usb()
                    self.show_firefox_kiosk()
                    time.sleep(3)
    
    def run(self):
        self.running = True
        
        if self.mode == 'usb':
            self.run_usb()
        elif self.mode == 'hybrid':
            self.run_hybrid()
        else:
            self.run_network()
    
    def run_network(self):
        self.running = True
        
        if not self.bind_socket():
            return
        
        logger.info("Waiting for network connection...")
        
        self.show_firefox_kiosk()
        
        while self.running:
            try:
                conn, addr = self.sock.accept()
                logger.info(f"Connected from {addr}")

                self.schedule_hide_when_window_present(['vaapisink', 'autovideosink', 'gst-launch-1.0'], appear_timeout=3.0, after_delay=5.0)
                
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
                
                if not self.start_decoder():
                    conn.close()
                    self.show_firefox_kiosk()
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
                self.show_firefox_kiosk()
                
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    logger.error(f"Connection error: {e}")
                    self.show_firefox_kiosk()
                    time.sleep(1)
    
    def stop(self):
        self.running = False
        
        if self.decoder_process:
            self.decoder_process.terminate()
            try:
                self.decoder_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.decoder_process.kill()
        
        self.stop_firefox_kiosk()
        
        if self.sock:
            self.sock.close()
        
        logger.info("Receiver stopped")

receiver = None

def signal_handler(sig, frame):
    logger.info("Shutting down...")
    if receiver:
        receiver.stop()
    sys.exit(0)

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='macOS External Display Receiver')
    parser.add_argument('--mode', choices=['network', 'usb', 'hybrid'], default='network',
                        help='Connection mode: network (TCP), usb (serial), or hybrid (auto-failover)')
    parser.add_argument('--host', default='0.0.0.0', help='Network bind address (network/hybrid mode)')
    parser.add_argument('--port', type=int, default=5900, help='Network port (network/hybrid mode)')
    parser.add_argument('--usb-device', help='USB serial device path (auto-detected if not specified)')
    
    args = parser.parse_args()
    
    if args.mode in ['usb', 'hybrid'] and not args.usb_device:
        usb_device = VideoReceiver.detect_usb_device()
        if usb_device:
            logger.info(f"Auto-detected USB device: {usb_device}")
        else:
            logger.warning("USB mode selected but no device detected. Available devices:")
            devices = VideoReceiver.detect_all_devices()
            if devices:
                for dev in devices:
                    logger.info(f"  {dev}")
            if args.mode == 'usb':
                logger.error("No USB device found for USB mode")
                sys.exit(1)
    else:
        usb_device = args.usb_device
    
    receiver = VideoReceiver(mode=args.mode, host=args.host, port=args.port, usb_device=usb_device)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info(f"Video receiver starting in {args.mode} mode")
    if args.mode in ['network', 'hybrid']:
        logger.info(f"  Network: {args.host}:{args.port}")
    if args.mode in ['usb', 'hybrid']:
        logger.info(f"  USB device: {usb_device or 'auto-detect'}")
    
    receiver.run()
