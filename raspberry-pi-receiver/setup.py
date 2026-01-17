#!/usr/bin/env python3

import subprocess
import os
import sys
import json
from pathlib import Path

class RaspberryPiSetup:
    def __init__(self):
        self.packages = [
            'gstreamer1.0-tools',
            'gstreamer1.0-plugins-base',
            'gstreamer1.0-plugins-good',
            'gstreamer1.0-plugins-bad',
            'gstreamer1.0-plugins-ugly',
            'gstreamer1.0-libav',
            'gstreamer1.0-vaapi',
            'libgstreamer1.0-0',
            'gstreamer1.0-nice',
            'wmctrl',
            'python3-gi',
            'python3-dev',
            'libgirepository1.0-dev',
            'python3-serial',
            'python3-pip',
        ]
    
    def check_system(self):
        try:
            result = subprocess.run(['uname', '-m'], capture_output=True, text=True)
            arch = result.stdout.strip()
            
            if 'arm' not in arch.lower():
                print(f"Warning: Architecture {arch} may not be optimized for hardware decoding")
            
            print(f"System: {arch}")
            return True
        except Exception as e:
            print(f"Error checking system: {e}")
            return False
    
    def install_dependencies(self):
        print("Installing dependencies...")
        
        try:
            subprocess.run(['sudo', 'apt-get', 'update'], check=True)
            subprocess.run(
                ['sudo', 'apt-get', 'install', '-y'] + self.packages,
                check=True
            )
            print("Dependencies installed successfully")
            return True
        except subprocess.CalledProcessError as e:
            print(f"Error installing dependencies: {e}")
            return False
    
    def verify_gstreamer(self):
        print("Verifying GStreamer installation...")
        
        try:
            result = subprocess.run(
                ['gst-launch-1.0', '--version'],
                capture_output=True,
                text=True,
                check=True
            )
            print(result.stdout)
            return True
        except Exception as e:
            print(f"GStreamer not found: {e}")
            return False
    
    def setup_service(self, user=None):
        if user is None:
            user = os.getlogin()
        
        service_content = f"""[Unit]
Description=DeskExtend Video Receiver
After=network.target

[Service]
Type=simple
User={user}
WorkingDirectory=/opt/deskextend
ExecStart=/usr/bin/python3 /opt/deskextend/receiver.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
"""
        
        try:
            os.makedirs('/opt/deskextend', exist_ok=True)
            
            with open('/tmp/deskextend.service', 'w') as f:
                f.write(service_content)
            
            subprocess.run(['sudo', 'cp', '/tmp/deskextend.service', '/etc/systemd/system/'], check=True)
            subprocess.run(['sudo', 'systemctl', 'daemon-reload'], check=True)
            subprocess.run(['sudo', 'systemctl', 'enable', 'deskextend'], check=True)
            
            print("Service installed successfully")
            return True
        except Exception as e:
            print(f"Error setting up service: {e}")
            return False
    
    def start_service(self):
        try:
            subprocess.run(['sudo', 'systemctl', 'start', 'deskextend'], check=True)
            print("Service started")
            return True
        except Exception as e:
            print(f"Error starting service: {e}")
            return False

if __name__ == '__main__':
    setup = RaspberryPiSetup()
    
    if not setup.check_system():
        sys.exit(1)
    
    if not setup.install_dependencies():
        sys.exit(1)
    
    if not setup.verify_gstreamer():
        sys.exit(1)
    
    if setup.setup_service():
        if setup.start_service():
            print("Raspberry Pi setup complete!")
    else:
        print("Setup completed with warnings")
