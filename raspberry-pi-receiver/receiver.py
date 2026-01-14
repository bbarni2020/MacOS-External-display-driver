#!/usr/bin/env python3

import socket
import struct
import subprocess
import signal
import sys
from pathlib import Path

class VideoReceiver:
    def __init__(self, host='0.0.0.0', port=5900):
        self.host = host
        self.port = port
        self.sock = None
        self.gstreamer_process = None
        self.running = False
        
    def setup_gstreamer_pipeline(self):
        pipeline = [
            'gst-launch-1.0',
            '-v',
            'fdsrc', 'fd=0',
            '!', 'h264parse',
            '!', 'v4l2h264dec',
            '!', 'video/x-raw,width=1920,height=1080',
            '!', 'kmssink', 'connector-id=32', 'plane-id=31',
            'fullscreen-overlay=1'
        ]
        return pipeline
    
    def start_gstreamer(self):
        try:
            pipeline = self.setup_gstreamer_pipeline()
            print(f"Starting GStreamer: {' '.join(pipeline)}")
            
            self.gstreamer_process = subprocess.Popen(
                pipeline,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE
            )
            print("GStreamer pipeline started")
            return True
        except Exception as e:
            print(f"Failed to start GStreamer: {e}")
            return False
    
    def connect_to_mac(self):
        try:
            self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.sock.bind((self.host, self.port))
            self.sock.settimeout(1.0)
            print(f"Listening on {self.host}:{self.port}")
            return True
        except Exception as e:
            print(f"Failed to bind socket: {e}")
            return False
    
    def receive_and_decode(self):
        self.running = True
        buffer = b''
        expected_size = 0
        
        print("Waiting for video stream from Mac...")
        
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
                
                if not data:
                    continue
                
                buffer += data
                
                while len(buffer) >= 4:
                    if expected_size == 0:
                        expected_size = struct.unpack('>I', buffer[:4])[0]
                        buffer = buffer[4:]
                    
                    if len(buffer) >= expected_size:
                        frame_data = buffer[:expected_size]
                        buffer = buffer[expected_size:]
                        expected_size = 0
                        
                        if self.gstreamer_process and self.gstreamer_process.stdin:
                            try:
                                self.gstreamer_process.stdin.write(frame_data)
                                self.gstreamer_process.stdin.flush()
                            except BrokenPipeError:
                                print("GStreamer pipe broken, restarting...")
                                self.start_gstreamer()
                    else:
                        break
                        
            except socket.timeout:
                continue
            except Exception as e:
                print(f"Receive error: {e}")
                break
    
    def stop(self):
        self.running = False
        
        if self.gstreamer_process:
            self.gstreamer_process.terminate()
            try:
                self.gstreamer_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.gstreamer_process.kill()
        
        if self.sock:
            self.sock.close()
        
        print("Receiver stopped")

def signal_handler(sig, frame):
    print("\nShutting down...")
    receiver.stop()
    sys.exit(0)

if __name__ == '__main__':
    receiver = VideoReceiver()
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    if not receiver.connect_to_mac():
        sys.exit(1)
    
    if not receiver.start_gstreamer():
        sys.exit(1)
    
    try:
        receiver.receive_and_decode()
    except KeyboardInterrupt:
        pass
    finally:
        receiver.stop()
