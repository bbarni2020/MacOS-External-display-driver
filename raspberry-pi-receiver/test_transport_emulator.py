#!/usr/bin/env python3

import sys
import os
import time
import struct
import socket
import threading

try:
    import serial
except ImportError:
    serial = None

class HybridTransportEmulator:
    def __init__(self, port=5900, usb_device=None):
        self.port = port
        self.usb_device = usb_device
        self.running = False
        self.test_data_size = 0
        
    def simulate_network_stream(self):
        print("[NETWORK] Starting network stream simulation")
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock.bind(('0.0.0.0', self.port))
        sock.listen(1)
        
        try:
            print(f"[NETWORK] Listening on 0.0.0.0:{self.port}")
            conn, addr = sock.accept()
            print(f"[NETWORK] Accepted connection from {addr}")
            
            for i in range(10):
                test_frame = struct.pack('>I', 1024) + (b'X' * 1024)
                conn.send(test_frame)
                self.test_data_size += len(test_frame)
                print(f"[NETWORK] Sent frame {i+1}: {len(test_frame)} bytes")
                time.sleep(0.1)
            
            conn.close()
        except Exception as e:
            print(f"[NETWORK] Error: {e}")
        finally:
            sock.close()
    
    def simulate_usb_stream(self):
        if not self.usb_device or serial is None:
            print("[USB] USB simulation skipped - no device or pyserial")
            return
        
        try:
            print(f"[USB] Opening {self.usb_device}")
            ser = serial.Serial(
                port=self.usb_device,
                baudrate=115200,
                timeout=1.0
            )
            
            for i in range(10):
                test_frame = struct.pack('>I', 1024) + (b'Y' * 1024)
                ser.write(test_frame)
                self.test_data_size += len(test_frame)
                print(f"[USB] Sent frame {i+1}: {len(test_frame)} bytes")
                time.sleep(0.1)
            
            ser.close()
            print("[USB] Connection closed")
        except Exception as e:
            print(f"[USB] Error: {e}")
    
    def run_hybrid(self):
        print("[HYBRID] Starting hybrid mode emulation")
        self.running = True
        
        usb_thread = threading.Thread(target=self.simulate_usb_stream, daemon=True)
        network_thread = threading.Thread(target=self.simulate_network_stream, daemon=True)
        
        usb_thread.start()
        time.sleep(0.5)
        network_thread.start()
        
        usb_thread.join(timeout=15)
        network_thread.join(timeout=15)
        
        print(f"[HYBRID] Total test data: {self.test_data_size} bytes")
        self.running = False

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser(description='Transport mode emulator for testing')
    parser.add_argument('--port', type=int, default=5900)
    parser.add_argument('--usb', help='USB device path')
    parser.add_argument('--mode', choices=['hybrid', 'network', 'usb'], default='hybrid')
    
    args = parser.parse_args()
    
    emulator = HybridTransportEmulator(port=args.port, usb_device=args.usb)
    
    if args.mode == 'hybrid':
        emulator.run_hybrid()
    elif args.mode == 'network':
        emulator.simulate_network_stream()
    elif args.mode == 'usb':
        emulator.simulate_usb_stream()
