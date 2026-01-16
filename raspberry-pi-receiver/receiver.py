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

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

class VideoReceiver:
    def __init__(self, host='0.0.0.0', port=5900):
        self.host = host
        self.port = port
        self.sock = None
        self.decoder_process = None
        self.running = False
        self.frame_count = 0
        self.last_fps_time = time.time()
        self.current_fps = 0
        self.decoder_type = None
        self.bytes_received = 0
    
    def detect_decoder_pipeline(self):
        pipelines = []

        has_v4l2_sink = os.path.exists('/dev/video0') and os.access('/dev/video0', os.W_OK)

        pipelines.append({
            'name': 'Software avdec + gtksink',
            'cmd': [
                'gst-launch-1.0', '-e',
                'fdsrc', 'fd=0',
                '!', 'queue', 'max-size-buffers=4', 'max-size-time=0', 'max-size-bytes=0',
                '!', 'h264parse',
                '!', 'avdec_h264', 'max-threads=4',
                '!', 'videoconvert',
                '!', 'gtksink', 'sync=false'
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
                '!', 'gtksink', 'sync=false'
            ]
        })

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
    
    def process_stream(self, conn):
        logger.info("Processing video stream...")
        
        buffer = b''
        
        while self.running:
            try:
                chunk = conn.recv(262144)
                if not chunk:
                    logger.info("Connection closed")
                    break
                
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
                    
            except socket.timeout:
                continue
            except Exception as e:
                logger.error(f"Receive error: {e}")
                break
        
        return True
    
    def run(self):
        self.running = True
        
        if not self.bind_socket():
            return
        
        logger.info("Waiting for connection...")
        
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
                
                logger.info("Connection closed, waiting for next connection...")
                
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
    receiver = VideoReceiver()
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    logger.info("Video receiver starting on 0.0.0.0:5900")
    receiver.run()
