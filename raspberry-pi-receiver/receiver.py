#!/usr/bin/env python3

import socket
import struct
import subprocess
import signal
import sys
import os
import time
import threading
from pathlib import Path
from http.server import HTTPServer, SimpleHTTPRequestHandler
import json

class VideoReceiver:
    def __init__(self, host='0.0.0.0', port=5900):
        self.host = host
        self.port = port
        self.sock = None
        self.gstreamer_process = None
        self.browser_process = None
        self.running = False
        self.connected = False
        self.streaming = False
        self.http_server = None
        self.http_thread = None
        self.video_clients = []
        self.video_lock = threading.Lock()
        self.waiting_html = self.load_waiting_html()
    
    def get_local_ip(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(('8.8.8.8', 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except Exception:
            return '0.0.0.0'
    
    def load_waiting_html(self):
        try:
            template_path = Path(__file__).parent / 'waiting.html'
            if template_path.exists():
                with open(template_path, 'r') as f:
                    html = f.read()
                local_ip = self.get_local_ip()
                html = html.replace('{{IP_ADDRESS}}', local_ip)
                html = html.replace('{{PORT}}', str(self.port))
                return html
        except Exception as e:
            print(f"Failed to load waiting.html: {e}")
        return None
    
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
        return [
            'gst-launch-1.0',
            '-v',
            'fdsrc', 'fd=0',
            '!', 'h264parse',
            '!', 'avdec_h264',
            '!', 'videoconvert',
            '!', 'autovideosink', 'sync=false'
        ]
    
    def start_waiting_page(self):
        try:
            browser = self.find_browser()
            if not browser:
                print("Warning: No compatible browser found, skipping browser display")

            
            if not self.start_http_server(8888):
                return False
            
            local_ip = self.get_local_ip()
            args = [browser]
            
            if browser == 'firefox':
                args.extend(['--new-window', '--fullscreen', '--kiosk'])
            else:
                args.extend(['--kiosk', '--noerrdialogs', '--disable-infobars', '--no-first-run', '--disable-session-crashed-bubble', '--disable-features=TranslateUI'])
            
            args.append(f'http://localhost:8888')
            
            self.browser_process = subprocess.Popen(
                args,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            print(f"Browser opened at http://localhost:8080 - Connect to {local_ip}:{self.port}")
            return True
        except Exception as e:
            print(f"Failed to start browser: {e}")
            return False
    
    def start_http_server(self, port=8080):
        try:
            receiver_instance = self
            
            class StreamHandler(SimpleHTTPRequestHandler):
                def do_GET(self):
                    if self.path == '/':
                        self.send_response(200)
                        self.send_header('Content-type', 'text/html')
                        self.end_headers()
                        
                        if receiver_instance.streaming:
                            html = receiver_instance.generate_stream_html()
                        else:
                            html = receiver_instance.waiting_html if receiver_instance.waiting_html else receiver_instance.generate_stream_html()
                        
                        self.wfile.write(html.encode())
                    elif self.path == '/stream':
                        if not receiver_instance.streaming:
                            self.send_error(503, 'Not streaming')
                            return
                        
                        self.send_response(200)
                        self.send_header('Content-Type', 'video/h264')
                        self.send_header('Cache-Control', 'no-cache')
                        self.send_header('Connection', 'keep-alive')
                        self.end_headers()
                        
                        with receiver_instance.video_lock:
                            receiver_instance.video_clients.append(self.wfile)
                        
                        try:
                            while receiver_instance.running and receiver_instance.streaming:
                                time.sleep(0.1)
                        finally:
                            with receiver_instance.video_lock:
                                if self.wfile in receiver_instance.video_clients:
                                    receiver_instance.video_clients.remove(self.wfile)
                    else:
                        self.send_error(404)
                
                def log_message(self, format, *args):
                    pass
            
            self.http_server = HTTPServer(('0.0.0.0', port), StreamHandler)
            self.http_thread = threading.Thread(target=self.http_server.serve_forever, daemon=True)
            self.http_thread.start()
            print(f"HTTP server started on port {port}")
            return True
        except Exception as e:
            print(f"Failed to start HTTP server: {e}")
            return False
    
    def generate_stream_html(self):
        local_ip = self.get_local_ip()
        return f'''<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>DeskExtend - Streaming</title>
    <style>
        * {{ margin: 0; padding: 0; box-sizing: border-box; }}
        body {{
            background: #000;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            overflow: hidden;
            cursor: none;
        }}
        #video-container {{
            width: 100%;
            height: 100%;
            display: flex;
            justify-content: center;
            align-items: center;
        }}
        canvas {{
            max-width: 100%;
            max-height: 100%;
            object-fit: contain;
        }}
        .status {{
            position: absolute;
            top: 20px;
            left: 20px;
            color: #0f0;
            font-family: monospace;
            font-size: 14px;
            background: rgba(0,0,0,0.7);
            padding: 10px;
            border-radius: 5px;
            z-index: 1000;
        }}
    </style>
</head>
<body>
    <div class="status" id="status">Connecting...</div>
    <div id="video-container">
        <canvas id="canvas"></canvas>
    </div>
    <script>
        const canvas = document.getElementById('canvas');
        const ctx = canvas.getContext('2d');
        const status = document.getElementById('status');
        
        canvas.width = window.innerWidth;
        canvas.height = window.innerHeight;
        
        window.addEventListener('resize', () => {{
            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;
        }});
        
        let ws = null;
        let reconnectInterval = null;
        
        function connect() {{
            try {{
                ws = new WebSocket('ws://{local_ip}:8081');
                
                ws.onopen = () => {{
                    status.textContent = 'Connected - Streaming';
                    status.style.color = '#0f0';
                    if (reconnectInterval) {{
                        clearInterval(reconnectInterval);
                        reconnectInterval = null;
                    }}
                }};
                
                ws.onmessage = (event) => {{
                    if (event.data instanceof Blob) {{
                        createImageBitmap(event.data).then(bitmap => {{
                            ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
                        }}).catch(() => {{}});
                    }}
                }};
                
                ws.onerror = () => {{
                    status.textContent = 'Connection Error';
                    status.style.color = '#f00';
                }};
                
                ws.onclose = () => {{
                    status.textContent = 'Disconnected - Reconnecting...';
                    status.style.color = '#ff0';
                    if (!reconnectInterval) {{
                        reconnectInterval = setInterval(() => {{
                            connect();
                        }}, 2000);
                    }}
                }};
            }} catch (e) {{
                status.textContent = 'Failed to connect';
                status.style.color = '#f00';
            }}
        }}
        
        connect();
    </script>
</body>
</html>'''
    
    def start_gstreamer(self):
        try:
            pipeline = [
                'gst-launch-1.0',
                '-v',
                'fdsrc', 'fd=0',
                '!', 'h264parse',
                '!', 'avdec_h264',
                '!', 'videoconvert',
                '!', 'jpegenc',
                '!', 'fdsink', 'fd=1'
            ]
            print(f"Starting decoder pipeline: {' '.join(pipeline)}")
            env = os.environ.copy()
            if 'DISPLAY' not in env:
                env['DISPLAY'] = ':0'
            self.gstreamer_process = subprocess.Popen(
                pipeline,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                env=env
            )
            threading.Thread(target=self.read_decoded_frames, daemon=True).start()
            print("Decoder pipeline started")
            return True
        except Exception as e:
            print(f"Failed to start decoder: {e}")
            return False
    
    def read_decoded_frames(self):
        while self.running and self.gstreamer_process:
            try:
                frame_data = self.gstreamer_process.stdout.read(65535)
                if frame_data:
                    with self.video_lock:
                        for client in self.video_clients[:]:
                            try:
                                client.write(frame_data)
                                client.flush()
                            except:
                                if client in self.video_clients:
                                    self.video_clients.remove(client)
            except:
                break
    
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
                            except Exception as e:
                                print(f"GStreamer write error: {e}")
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
        
        if self.http_server:
            self.http_server.shutdown()
            self.http_server = None
        
        if self.browser_process:
            self.browser_process.terminate()
            try:
                self.browser_process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.browser_process.kill()
            self.browser_process = None
        
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
    
    receiver.start_waiting_page()
    
    while receiver.running:
        if not receiver.connect_to_mac():
            time.sleep(5)
            continue
        
        initial_data, addr = receiver.wait_for_connection()
        
        if not initial_data or not receiver.running:
            time.sleep(5)
            continue
        
        if not receiver.start_gstreamer():
            receiver.streaming = False
            time.sleep(5)
            continue
        
        receiver.streaming = True
        print("Started streaming to browser")
        
        try:
            receiver.receive_and_decode(initial_data)
        except KeyboardInterrupt:
            break
        except Exception as e:
            print(f"Streaming error: {e}")
        finally:
            receiver.streaming = False
            receiver.connected = False
            print("Stopped streaming, showing waiting page")
            if receiver.gstreamer_process:
                receiver.gstreamer_process.terminate()
                try:
                    receiver.gstreamer_process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    receiver.gstreamer_process.kill()
                receiver.gstreamer_process = None
            time.sleep(2)
