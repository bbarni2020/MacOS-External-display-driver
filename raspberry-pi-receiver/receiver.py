#!/usr/bin/env python3

import socket
import struct
import subprocess
import signal
import sys
import threading
import time
import os

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
    
    def setup_decoder_pipeline(self):
        hw_decoder = 'v4l2h264dec'
        hw_sink = 'kmssink'
        
        pipeline = [
            'gst-launch-1.0', '-e',
            'fdsrc', 'fd=0',
            '!', 'queue', 'max-size-buffers=2', 'max-size-time=0', 'max-size-bytes=0',
            '!', 'h264parse',
            '!', hw_decoder,
            '!', 'queue', 'max-size-buffers=2',
            '!', 'videoconvert',
            '!', hw_sink, 'fullscreen-overlay=1', 'sync=false', 'max-lateness=-1', 'qos=false'
        ]
        
        return pipeline
    
    def start_decoder(self):
        try:
            pipeline = self.setup_decoder_pipeline()
            print(f"Starting decoder: {' '.join(pipeline)}")
            
            env = os.environ.copy()
            if 'DISPLAY' not in env:
                env['DISPLAY'] = ':0'
            
            self.decoder_process = subprocess.Popen(
                pipeline,
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=env,
                bufsize=0
            )
            
            print("Decoder started")
            return True
        except Exception as e:
            print(f"Decoder start failed: {e}")
            return False
    
    def bind_socket(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.sock.bind((self.host, self.port))
            self.sock.listen(1)
            self.sock.settimeout(5.0)
            print(f"Listening on {self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"Socket bind failed: {e}")
            return False
    
    def update_fps(self):
        self.frame_count += 1
        now = time.time()
        elapsed = now - self.last_fps_time
        if elapsed >= 1.0:
            self.current_fps = self.frame_count / elapsed
            print(f"FPS: {self.current_fps:.1f}")
            self.frame_count = 0
            self.last_fps_time = now
    
    def receive_exact(self, conn, size):
        data = b''
        while len(data) < size:
            chunk = conn.recv(min(size - len(data), 65536))
            if not chunk:
                return None
            data += chunk
        return data
    
    def process_stream(self, conn):
        print("Processing video stream...")
        
        buffer = b''
        
        while self.running:
            try:
                chunk = conn.recv(131072)
                if not chunk:
                    print("Connection closed")
                    break
                
                buffer += chunk
                
                while len(buffer) >= 4:
                    frame_size = struct.unpack('>I', buffer[:4])[0]
                    
                    if frame_size > 10485760:
                        print(f"Invalid frame size: {frame_size}")
                        buffer = buffer[1:]
                        continue
                    
                    if len(buffer) < 4 + frame_size:
                        break
                    
                    frame_data = buffer[4:4 + frame_size]
                    buffer = buffer[4 + frame_size:]
                    
                    if self.decoder_process and self.decoder_process.stdin:
                        try:
                            self.decoder_process.stdin.write(frame_data)
                            self.update_fps()
                        except BrokenPipeError:
                            print("Decoder pipe broken")
                            return False
                        except Exception as e:
                            print(f"Decoder write error: {e}")
                            return False
                    
            except socket.timeout:
                continue
            except Exception as e:
                print(f"Receive error: {e}")
                break
        
        return True
    
    def run(self):
        self.running = True
        
        if not self.bind_socket():
            return
        
        print("Waiting for connection...")
        
        while self.running:
            try:
                conn, addr = self.sock.accept()
                print(f"Connected from {addr}")
                
                conn.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                conn.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 2097152)
                
                if not self.start_decoder():
                    conn.close()
                    continue
                
                self.frame_count = 0
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
                
                print("Connection closed, waiting for next connection...")
                
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"Connection error: {e}")
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
        
        print("Receiver stopped")

receiver = None

def signal_handler(sig, frame):
    print("\nShutting down...")
    if receiver:
        receiver.stop()
    sys.exit(0)

if __name__ == '__main__':
    receiver = VideoReceiver()
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    receiver.run()
