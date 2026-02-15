#!/usr/bin/env python3

import sys
import os
import time
import socket
import struct
import glob
import subprocess
from datetime import datetime

try:
    import serial
    from serial.tools import list_ports
except ImportError:
    serial = None
    list_ports = None

class TransportTester:
    def __init__(self):
        self.test_results = []
        
    def log(self, level, message):
        timestamp = datetime.now().strftime("%H:%M:%S.%f")[:-3]
        formatted = f"[{timestamp}] [{level:5}] {message}"
        print(formatted)
        self.test_results.append(formatted)
    
    def info(self, msg): self.log("INFO", msg)
    def warn(self, msg): self.log("WARN", msg)
    def error(self, msg): self.log("ERROR", msg)
    def success(self, msg): self.log("OK", msg)
    
    def separator(self):
        line = "=" * 70
        print(line)
        self.test_results.append(line)
    
    def test_system_info(self):
        self.separator()
        self.info("SYSTEM INFORMATION")
        self.separator()
        
        try:
            hostname = subprocess.check_output(['hostname']).decode().strip()
            self.info(f"Hostname: {hostname}")
        except:
            self.warn("Could not get hostname")
        
        try:
            uname = subprocess.check_output(['uname', '-a']).decode().strip()
            self.info(f"System: {uname}")
        except:
            self.warn("Could not get system info")
        
        try:
            with open('/proc/cpuinfo', 'r') as f:
                for line in f:
                    if 'Model' in line or 'Hardware' in line:
                        self.info(f"CPU: {line.strip()}")
                        break
        except:
            self.warn("Could not read CPU info")
        
        try:
            with open('/sys/class/thermal/thermal_zone0/temp', 'r') as f:
                temp = int(f.read().strip()) / 1000
                self.info(f"CPU Temperature: {temp}°C")
        except:
            self.warn("Could not read temperature")
        
        self.info(f"Python: {sys.version}")
        
    def test_usb_devices(self):
        self.separator()
        self.info("USB DEVICE DETECTION")
        self.separator()
        
        if serial is None:
            self.error("pyserial not installed - install with: pip3 install pyserial")
            return []
        
        devices = []
        patterns = [
            '/dev/ttyUSB*',
            '/dev/ttyACM*',
            '/dev/cu.usbmodem*',
            '/dev/tty.usbmodem*',
            '/dev/serial/by-id/*'
        ]
        
        for pattern in patterns:
            found = glob.glob(pattern)
            if found:
                self.info(f"Pattern '{pattern}': found {len(found)} device(s)")
                for dev in found:
                    devices.append(dev)
                    self.info(f"  - {dev}")
        
        if not devices:
            self.warn("No USB serial devices found")
            self.info("Checking USB devices with pyserial...")
            
            if list_ports:
                ports = list(list_ports.comports())
                if ports:
                    self.info(f"Found {len(ports)} serial ports:")
                    for port in ports:
                        self.info(f"  - {port.device}: {port.description}")
                        devices.append(port.device)
                else:
                    self.warn("No serial ports detected by pyserial")
        
        return devices
    
    def test_usb_connection(self, device):
        self.separator()
        self.info(f"USB CONNECTION TEST: {device}")
        self.separator()
        
        if serial is None:
            self.error("pyserial not installed")
            return False
        
        try:
            self.info(f"Opening {device} at 115200 baud...")
            ser = serial.Serial(
                port=device,
                baudrate=115200,
                timeout=1.0,
                write_timeout=1.0
            )
            self.success(f"Successfully opened {device}")
            
            self.info(f"Port: {ser.port}")
            self.info(f"Baudrate: {ser.baudrate}")
            self.info(f"Timeout: {ser.timeout}s")
            self.info(f"Write Timeout: {ser.write_timeout}s")
            
            self.info("Testing read (waiting 2 seconds)...")
            time.sleep(2)
            
            if ser.in_waiting:
                self.info(f"Data available: {ser.in_waiting} bytes")
                data = ser.read(min(ser.in_waiting, 100))
                self.info(f"Sample data: {data[:50]}")
            else:
                self.warn("No data available to read")
            
            self.info("Testing write...")
            test_data = b"TEST\x00\x00\x00\x04TEST"
            ser.write(test_data)
            ser.flush()
            self.success(f"Successfully wrote {len(test_data)} bytes")
            
            ser.close()
            self.success("USB connection test passed")
            return True
            
        except serial.SerialException as e:
            self.error(f"Serial error: {e}")
            return False
        except Exception as e:
            self.error(f"Unexpected error: {e}")
            return False
    
    def test_network_info(self):
        self.separator()
        self.info("NETWORK CONFIGURATION")
        self.separator()
        
        try:
            result = subprocess.check_output(['ip', 'addr', 'show']).decode()
            for line in result.split('\n'):
                if 'inet ' in line:
                    self.info(line.strip())
        except:
            try:
                result = subprocess.check_output(['ifconfig']).decode()
                for line in result.split('\n'):
                    if 'inet' in line:
                        self.info(line.strip())
            except:
                self.warn("Could not get network info")
        
        self.info("\nNetwork connectivity test:")
        for host in ['8.8.8.8', 'google.com']:
            try:
                result = subprocess.run(
                    ['ping', '-c', '1', '-W', '2', host],
                    capture_output=True,
                    timeout=3
                )
                if result.returncode == 0:
                    self.success(f"Can reach {host}")
                else:
                    self.warn(f"Cannot reach {host}")
            except:
                self.warn(f"Ping test failed for {host}")
    
    def test_network_socket(self, host='0.0.0.0', port=5900):
        self.separator()
        self.info(f"NETWORK SOCKET TEST: {host}:{port}")
        self.separator()
        
        try:
            self.info("Creating TCP socket...")
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            
            self.info(f"Binding to {host}:{port}...")
            sock.bind((host, port))
            
            self.info("Listening for connections...")
            sock.listen(1)
            sock.settimeout(5.0)
            
            self.success(f"Socket bound successfully to {host}:{port}")
            self.info("Waiting 5 seconds for incoming connection...")
            
            try:
                conn, addr = sock.accept()
                self.success(f"Connection received from {addr}")
                
                self.info("Reading data...")
                data = conn.recv(4096)
                if data:
                    self.success(f"Received {len(data)} bytes")
                    self.info(f"Data preview: {data[:50]}")
                else:
                    self.warn("No data received")
                
                conn.close()
            except socket.timeout:
                self.warn("No connection received within timeout")
            
            sock.close()
            self.success("Network socket test completed")
            return True
            
        except OSError as e:
            if e.errno == 98:
                self.error(f"Port {port} already in use")
            else:
                self.error(f"Socket error: {e}")
            return False
        except Exception as e:
            self.error(f"Unexpected error: {e}")
            return False
    
    def test_gstreamer(self):
        self.separator()
        self.info("GSTREAMER AVAILABILITY")
        self.separator()
        
        commands = [
            ('gst-launch-1.0', ['gst-launch-1.0', '--version']),
            ('gst-inspect-1.0', ['gst-inspect-1.0', 'h264parse']),
            ('avdec_h264', ['gst-inspect-1.0', 'avdec_h264']),
            ('vaapisink', ['gst-inspect-1.0', 'vaapisink']),
        ]
        
        for name, cmd in commands:
            try:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    timeout=3,
                    text=True
                )
                if result.returncode == 0:
                    self.success(f"{name}: available")
                    if '--version' in cmd:
                        for line in result.stdout.split('\n'):
                            if 'GStreamer' in line:
                                self.info(f"  {line.strip()}")
                                break
                else:
                    self.warn(f"{name}: not found")
            except FileNotFoundError:
                self.error(f"{name}: not installed")
            except Exception as e:
                self.warn(f"{name}: test failed - {e}")
    
    def test_display(self):
        self.separator()
        self.info("DISPLAY DETECTION")
        self.separator()
        
        display = os.environ.get('DISPLAY', None)
        if display:
            self.success(f"DISPLAY environment variable: {display}")
        else:
            self.warn("DISPLAY environment variable not set")
            self.info("Setting DISPLAY=:0 for tests")
            os.environ['DISPLAY'] = ':0'
        
        try:
            result = subprocess.run(
                ['xrandr', '--query'],
                capture_output=True,
                text=True,
                timeout=2,
                env=os.environ
            )
            
            if result.returncode == 0:
                self.success("xrandr available")
                connected_displays = []
                for line in result.stdout.split('\n'):
                    if ' connected' in line and 'disconnected' not in line:
                        connected_displays.append(line.strip())
                        self.info(f"Display: {line.strip()}")
                
                if connected_displays:
                    self.success(f"Found {len(connected_displays)} connected display(s)")
                else:
                    self.warn("No displays detected as connected")
            else:
                self.error("xrandr failed")
        except FileNotFoundError:
            self.error("xrandr not installed")
        except Exception as e:
            self.error(f"Display test failed: {e}")
    
    def test_permissions(self):
        self.separator()
        self.info("PERMISSIONS CHECK")
        self.separator()
        
        try:
            uid = os.getuid()
            self.info(f"Running as UID: {uid}")
            
            if uid == 0:
                self.warn("Running as root - not recommended for normal operation")
            else:
                self.info("Running as non-root user")
            
            try:
                import pwd
                user = pwd.getpwuid(uid).pw_name
                self.info(f"Username: {user}")
                
                groups_result = subprocess.check_output(['groups']).decode().strip()
                self.info(f"Groups: {groups_result}")
                
                if 'dialout' in groups_result or 'uucp' in groups_result:
                    self.success("User has serial port access group")
                else:
                    self.warn("User may not have serial port access")
                    self.info("Add user to dialout group: sudo usermod -a -G dialout $USER")
            except:
                pass
                
        except Exception as e:
            self.warn(f"Permission check failed: {e}")
    
    def run_all_tests(self):
        self.separator()
        self.info("MACOS EXTERNAL DISPLAY - TRANSPORT TEST SUITE")
        self.separator()
        
        start_time = time.time()
        
        self.test_system_info()
        self.test_permissions()
        self.test_display()
        self.test_gstreamer()
        
        usb_devices = self.test_usb_devices()
        
        if usb_devices:
            for device in usb_devices[:2]:
                self.test_usb_connection(device)
        
        self.test_network_info()
        self.test_network_socket()
        
        elapsed = time.time() - start_time
        
        self.separator()
        self.success(f"ALL TESTS COMPLETED IN {elapsed:.2f} SECONDS")
        self.separator()
        
        print("\n")
        self.info("RECOMMENDATIONS:")
        
        if serial is None:
            print("  • Install pyserial: pip3 install pyserial")
        
        if not usb_devices:
            print("  • Connect USB cable between Mac and Raspberry Pi")
            print("  • Ensure USB gadget mode is configured on Raspberry Pi")
        
        print("  • For USB mode: sudo python3 receiver.py --mode usb")
        print("  • For Network mode: python3 receiver.py --mode network")
        print("  • For Hybrid mode: python3 receiver.py --mode hybrid")
        
        print("\n")
        return self.test_results

def main():
    tester = TransportTester()
    results = tester.run_all_tests()
    
    log_file = f"transport_test_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    try:
        with open(log_file, 'w') as f:
            f.write('\n'.join(results))
        print(f"\nTest results saved to: {log_file}")
    except Exception as e:
        print(f"\nCould not save log file: {e}")

if __name__ == '__main__':
    main()
