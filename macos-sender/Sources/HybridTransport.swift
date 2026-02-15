import Foundation
import Network

class HybridTransport {
    enum TransportMode {
        case usb(devicePath: String)
        case network(host: String)
        case hybrid(usbPath: String, networkHost: String)
    }
    
    private var usbTransport: USBTransport?
    private var networkTransport: NetworkTransport?
    private let queue = DispatchQueue(label: "com.virtualdisplay.hybrid")
    
    private var statusCallback: ((Bool, String) -> Void)?
    private var logCallback: ((String) -> Void)?
    private var mode: TransportMode?
    
    private var usbConnected = false
    private var networkConnected = false
    
    var currentBitrate: Double {
        let usb = usbTransport?.currentBitrate ?? 0
        let network = networkTransport?.currentBitrate ?? 0
        return max(usb, network)
    }
    
    var connectedAddress: String {
        switch mode {
        case .hybrid:
            if usbConnected && networkConnected {
                return "Hybrid: USB + Network"
            } else if usbConnected {
                return usbTransport?.connectedAddress ?? "USB"
            } else if networkConnected {
                return networkTransport?.connectedAddress ?? "Network"
            }
            return "Not connected"
        case .usb:
            return usbTransport?.connectedAddress ?? "Not connected"
        case .network:
            return networkTransport?.connectedAddress ?? "Not connected"
        case .none:
            return "Not connected"
        }
    }
    
    init(statusCallback: ((Bool, String) -> Void)? = nil, logCallback: ((String) -> Void)? = nil) {
        self.statusCallback = statusCallback
        self.logCallback = logCallback
    }
    
    func connectUSB(devicePath: String) {
        mode = .usb(devicePath: devicePath)
        
        usbTransport = USBTransport(
            devicePath: devicePath,
            statusCallback: { [weak self] connected, address in
                self?.usbConnected = connected
                self?.statusCallback?(connected, address)
            },
            logCallback: logCallback
        )
        
        usbTransport?.connect()
    }
    
    func connectNetwork(host: String) {
        mode = .network(host: host)
        
        networkTransport = NetworkTransport(
            statusCallback: { [weak self] connected, address in
                self?.networkConnected = connected
                self?.statusCallback?(connected, address)
            },
            logCallback: logCallback
        )
        
        networkTransport?.connect(to: host)
    }
    
    func connectHybrid(usbPath: String, networkHost: String) {
        mode = .hybrid(usbPath: usbPath, networkHost: networkHost)
        
        usbTransport = USBTransport(
            devicePath: usbPath,
            statusCallback: { [weak self] connected, address in
                self?.usbConnected = connected
                self?.logCallback?("USB: \(connected ? "connected" : "disconnected")")
                self?.updateHybridStatus()
            },
            logCallback: logCallback
        )
        
        networkTransport = NetworkTransport(
            statusCallback: { [weak self] connected, address in
                self?.networkConnected = connected
                self?.logCallback?("Network: \(connected ? "connected" : "disconnected")")
                self?.updateHybridStatus()
            },
            logCallback: logCallback
        )
        
        usbTransport?.connect()
        networkTransport?.connect(to: networkHost)
    }
    
    private func updateHybridStatus() {
        let connected = usbConnected || networkConnected
        statusCallback?(connected, connectedAddress)
    }
    
    func send(data: Data) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            switch self.mode {
            case .usb:
                if self.usbConnected {
                    self.usbTransport?.send(data: data)
                }
            case .network:
                if self.networkConnected {
                    self.networkTransport?.send(data: data)
                }
            case .hybrid:
                if self.usbConnected {
                    self.usbTransport?.send(data: data)
                } else if self.networkConnected {
                    self.networkTransport?.send(data: data)
                }
            case .none:
                break
            }
        }
    }
    
    func stop() {
        queue.async { [weak self] in
            self?.usbTransport?.stop()
            self?.networkTransport?.stop()
            self?.usbTransport = nil
            self?.networkTransport = nil
            self?.usbConnected = false
            self?.networkConnected = false
            self?.mode = nil
        }
    }
}
}
