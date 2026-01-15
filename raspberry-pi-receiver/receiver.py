#!/usr/bin/env python3

import socket
import struct
import subprocess
import signal
import sys
import os
import time
from pathlib import Path

class VideoReceiver:
    def __init__(self, host='0.0.0.0', port=5900):
        self.host = host
        self.port = port
        self.sock = None
        self.gstreamer_process = None
        self.browser_process = None
        self.running = False
        self.connected = False
    
    def get_local_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return '0.0.0.0'
    
    def find_browser(self):
        browsers = [
            'firefox',
            'chromium-browser',
            'chromium',
            'epiphany',
            'midori'
        ]
        
        for browser in browsers:
            if subprocess.run(['which', browser], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0:
                return browser
        
        return None
        
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
    
    def start_waiting_page(self):
        try:
            template_path = Path(__file__).parent / 'waiting.html'
            if not template_path.exists():
                print(f"Warning: {template_path} not found, skipping browser display")
                return False
            
            browser = self.find_browser()
            if not browser:
                print("Warning: No compatible browser found, skipping waiting page")
                return False
            
            local_ip = self.get_local_ip()
            
            with open(template_path, 'r') as f:
                html_content = f.read()
            
            html_content = html_content.replace('{{IP_ADDRESS}}', local_ip)
            html_content = html_content.replace('{{PORT}}', str(self.port))
            
            runtime_html = Path(__file__).parent / 'waiting_runtime.html'
            with open(runtime_html, 'w') as f:
                f.write(html_content)
            
            args = [browser]
            
            if browser == 'firefox':
                args.extend(['--new-window', '--fullscreen', '--kiosk'])
            else:
                args.extend(['--kiosk', '--noerrdialogs', '--disable-infobars', '--no-first-run', '--disable-session-crashed-bubble', '--disable-features=TranslateUI'])
            
            args.append(f'file://{runtime_html.absolute()}')
            
            self.browser_process = subprocess.Popen(
                args,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            print(f"Waiting page displayed using {browser} - Connect to {local_ip}:{self.port}")
            return True
        except Exception as e:
            print(f"Failed to start browser: {e}")
            return False
    
    def stop_waiting_page(self):
        if self.browser_process:
            self.browser_process.terminate()
            try:
                self.browser_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.browser_process.kill()
            self.browser_process = None
            subprocess.run(['pkill', '-f', 'chromium-browser'], 
                         stdout=subprocess.DEVNULL, 
                         stderr=subprocess.DEVNULL)
    
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
    
    def wait_for_connection(self):
        print("Waiting for initial connection from Mac...")
        
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
                if data and len(data) > 0:
                    print(f"Connection established from {addr}")
                    self.connected = True
                    return data, addr
            except socket.timeout:
                continue
            except Exception as e:
                if self.running:
                    print(f"Error waiting for connection: {e}")
                continue
    
    def receive_and_decode(self, initial_data=None):
        self.running = True
        buffer = initial_data if initial_data else b''
        expected_size = 0
        
        print("Processing video stream...")
        
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
        
        self.stop_waiting_page()
        
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
    receiver.running = True
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    while receiver.running:
        receiver.start_waiting_page()
        
        if not receiver.connect_to_mac():
            receiver.stop_waiting_page()
            time.sleep(5)
            continue
        
        initial_data, addr = receiver.wait_for_connection()
        
        if not initial_data or not receiver.running:
            receiver.stop_waiting_page()
            time.sleep(5)
            continue
        
        receiver.stop_waiting_page()
        
        if not receiver.start_gstreamer():
            receiver.stop_waiting_page()
            time.sleep(5)
            continue
        
        try:
            receiver.receive_and_decode(initial_data)
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Streaming error: {e}")
        finally:
            receiver.connected = False
            if receiver.gstreamer_process:
                receiver.gstreamer_process.terminate()
                try:
                    receiver.gstreamer_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    receiver.gstreamer_process.kill()
                receiver.gstreamer_process = None
            time.sleep(5)
