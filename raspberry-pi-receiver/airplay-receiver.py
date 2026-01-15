#!/usr/bin/env python3

import subprocess
import signal
import sys
import os
import time
import socket

class AirPlayReceiver:
    def __init__(self, device_name="RaspberryPi Display"):
        self.device_name = device_name
        self.receiver_process = None
        self.running = False
        self.receiver_type = None
        
    def detect_airplay_server(self):
        servers = [
            {
                'name': 'UxPlay',
                'check_cmd': ['which', 'uxplay'],
                'run_cmd': ['uxplay', '-n', self.device_name, '-s', '1920x1080', '-fs']
            },
            {
                'name': 'RPiPlay',
                'check_cmd': ['which', 'rpiplay'],
                'run_cmd': ['rpiplay', '-n', self.device_name, '-l']
            }
        ]
        
        for server in servers:
            try:
                result = subprocess.run(server['check_cmd'], 
                                      capture_output=True, 
                                      timeout=2)
                if result.returncode == 0:
                    return server
            except:
                continue
        
        return None
    
    def install_uxplay(self):
        print("AirPlay server not found. Installation instructions:")
        print("\nFor UxPlay (recommended):")
        print("  sudo apt-get update")
        print("  sudo apt-get install -y cmake libssl-dev libplist-dev libavahi-compat-libdnssd-dev")
        print("  sudo apt-get install -y libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev")
        print("  git clone https://github.com/FDH2/UxPlay.git")
        print("  cd UxPlay && mkdir build && cd build")
        print("  cmake .. && make")
        print("  sudo make install")
        print("\nFor RPiPlay (alternative):")
        print("  sudo apt-get install -y cmake libavahi-compat-libdnssd-dev libplist-dev")
        print("  sudo apt-get install -y libssl-dev libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev")
        print("  git clone https://github.com/FD-/RPiPlay.git")
        print("  cd RPiPlay && mkdir build && cd build")
        print("  cmake .. && make")
        print("  sudo make install")
        
        return False
    
    def get_hostname(self):
        try:
            return socket.gethostname()
        except:
            return "raspberrypi"
    
    def get_ip_address(self):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
            return ip
        except:
            return "unknown"
    
    def start_receiver(self):
        server_info = self.detect_airplay_server()
        
        if not server_info:
            return self.install_uxplay()
        
        self.receiver_type = server_info['name']
        print(f"Starting {self.receiver_type}...")
        print(f"Device name: {self.device_name}")
        print(f"Hostname: {self.get_hostname()}")
        print(f"IP Address: {self.get_ip_address()}")
        print("\nWaiting for AirPlay connections from Apple devices...")
        print("Look for this device in Control Center > Screen Mirroring\n")
        
        try:
            env = os.environ.copy()
            if 'DISPLAY' not in env:
                env['DISPLAY'] = ':0'
            
            self.receiver_process = subprocess.Popen(
                server_info['run_cmd'],
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                bufsize=1,
                universal_newlines=True
            )
            
            while self.running and self.receiver_process.poll() is None:
                line = self.receiver_process.stdout.readline()
                if line:
                    print(line.rstrip())
            
            if self.receiver_process.poll() is not None:
                print(f"\n{self.receiver_type} exited with code {self.receiver_process.returncode}")
                return False
                
        except Exception as e:
            print(f"Error starting receiver: {e}")
            return False
        
        return True
    
    def run(self):
        self.running = True
        
        while self.running:
            if not self.start_receiver():
                if not self.running:
                    break
                print("\nReceiver stopped. Restarting in 3 seconds...")
                time.sleep(3)
    
    def stop(self):
        self.running = False
        
        if self.receiver_process:
            print("\nStopping AirPlay receiver...")
            self.receiver_process.terminate()
            try:
                self.receiver_process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.receiver_process.kill()
            
        print("AirPlay receiver stopped")

receiver = None

def signal_handler(sig, frame):
    print("\nShutting down...")
    if receiver:
        receiver.stop()
    sys.exit(0)

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='AirPlay Screen Mirroring Receiver')
    parser.add_argument('-n', '--name', 
                       default='RaspberryPi Display',
                       help='Device name visible to AirPlay clients')
    
    args = parser.parse_args()
    
    receiver = AirPlayReceiver(device_name=args.name)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    receiver.run()
