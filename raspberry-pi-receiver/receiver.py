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

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class VideoReceiver:
    def __init__(self, host='0.0.0.0', port=5900, mode='network', usb_device=None):
        self.host = host
        self.port = port
        self.mode = mode
        self.usb_device = usb_device or self.detect_usb_device()
        self.sock = None
        self.serial_conn = None
        self.decoder_process = None
        self.running = False
        self.frame_count = 0
        self.last_fps_time = time.time()
        self.current_fps = 0
        self.decoder_type = None
        self.bytes_received = 0
    
    @staticmethod
    def detect_usb_device():
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
    
    def detect_decoder_pipeline(self):
        pipelines = []

        has_v4l2_sink = os.path.exists('/dev/video0') and os.access('/dev/video0', os.W_OK)

        pipelines.append({
            'name': 'Hardware v4l2 + autovideosink',
            'cmd': [
                'gst-launch-1.0', '-e',
                'fdsrc', 'fd=0',
                '!', 'queue', 'max-size-buffers=3', 'max-size-time=0', 'max-size-bytes=0',
                '!', 'h264parse',
                '!', 'v4l2h264dec', 'capture-io-mode=mmap',
                '!', 'videoconvert',
                '!', 'gtksink', 'fullscreen=true', 'sync=false'
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

        pipelines.append({
            'name': 'Software avdec + autovideosink',
            'cmd': [
                'gst-launch-1.0', '-e',
                'fdsrc', 'fd=0',
                '!', 'queue', 'max-size-buffers=4', 'max-size-time=0', 'max-size-bytes=0',
                '!', 'h264parse',
                '!', 'avdec_h264', 'max-threads=4',
                '!', 'videoconvert',
                '!', 'gtksink', 'fullscreen=true', 'sync=false'
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
        """Read from socket or serial connection"""
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
        
        while self.running:
            try:
                if not self.open_usb():
                    logger.warning("Retrying USB connection in 3 seconds...")
                    time.sleep(3)
                    continue
                
                if not self.start_decoder():
                    self.close_usb()
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
                time.sleep(1)
                
            except Exception as e:
                if self.running:
                    logger.error(f"USB error: {e}")
                    self.close_usb()
                    time.sleep(3)
    
    def run_hybrid(self):
        """Run hybrid mode: try USB first, fallback to network"""
        self.running = True
        
        logger.info("Starting hybrid mode (USB priority with network fallback)")
        
        network_thread = None
        usb_active = False
        
        while self.running:
            try:
                if self.usb_device and not usb_active:
                    logger.info(f"Attempting USB connection: {self.usb_device}")
                    if self.open_usb():
                        usb_active = True
                        if not self.start_decoder():
                            self.close_usb()
                            usb_active = False
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
                            time.sleep(1)
                            continue
                    else:
                        logger.warning("USB connection failed, falling back to network...")
                
                logger.info(f"Listening on network {self.host}:{self.port}")
                if not self.bind_socket():
                    time.sleep(3)
                    continue
                
                logger.info("Waiting for network connection...")
                self.sock.settimeout(2.0)
                
                try:
                    conn, addr = self.sock.accept()
                    logger.info(f"Connected from {addr}")
                    
                    conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                    conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
                    
                    if not self.start_decoder():
                        conn.close()
                        self.sock.close()
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
                    
                except socket.timeout:
                    if self.usb_device:
                        logger.info("No network connection, retrying USB...")
                    continue
                    
            except Exception as e:
                if self.running:
                    logger.error(f"Hybrid mode error: {e}")
                    if self.sock:
                        self.sock.close()
                    self.close_usb()
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
        
        while self.running:
            try:
                conn, addr = self.sock.accept()
                logger.info(f"Connected from {addr}")
                
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
                
                if not self.start_decoder():
                    conn.close()
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
                
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    logger.error(f"Connection error: {e}")
                    time.sleep(1)
    
    def stop(self):
        self.running = False
        
        if self.decoder_process:
            self.decoder_process.terminate()
            try:
                self.decoder_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.decoder_process.kill()
        
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
