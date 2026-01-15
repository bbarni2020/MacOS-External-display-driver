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
    
    var currentBitrate: Double {
        let usb = usbTransport?.currentBitrate ?? 0
        let network = networkTransport?.currentBitrate ?? 0
        return max(usb, network)
    }
    
    var connectedAddress: String {
        if let usb = usbTransport, usb.connectedAddress != "Not connected" {
            return usb.connectedAddress
        }
        return networkTransport?.connectedAddress ?? "Not connected"
    }
    
    init(statusCallback: ((Bool, String) -> Void)? = nil, logCallback: ((String) -> Void)? = nil) {
        self.statusCallback = statusCallback
        self.logCallback = logCallback
    }
    
    func connectUSB(devicePath: String) {
        mode = .usb(devicePath: devicePath)
        
        usbTransport = USBTransport(
            devicePath: devicePath,
            statusCallback: statusCallback,
            logCallback: logCallback
        )
        
        usbTransport?.connect()
    }
    
    func connectNetwork(host: String) {
        mode = .network(host: host)
        
        networkTransport = NetworkTransport(
            statusCallback: statusCallback,
            logCallback: logCallback
        )
        
        networkTransport?.connect(to: host)
    }
    
    func connectHybrid(usbPath: String, networkHost: String) {
        mode = .hybrid(usbPath: usbPath, networkHost: networkHost)
        
        usbTransport = USBTransport(
            devicePath: usbPath,
            statusCallback: { [weak self] connected, address in
                self?.logCallback?("USB: \(connected ? "connected" : "disconnected")")
            },
            logCallback: logCallback
        )
        
        networkTransport = NetworkTransport(
            statusCallback: { [weak self] connected, address in
                self?.logCallback?("Network: \(connected ? "connected" : "disconnected")")
            },
            logCallback: logCallback
        )
        
        usbTransport?.connect()
        networkTransport?.connect(to: networkHost)
    }
    
    func send(data: Data) {
        queue.async { [weak self] in
            if let usb = self?.usbTransport {
                usb.send(data: data)
            } else if let network = self?.networkTransport {
                network.send(data: data)
            }
        }
    }
    
    func stop() {
        queue.async { [weak self] in
            self?.usbTransport?.stop()
            self?.networkTransport?.stop()
            self?.usbTransport = nil
            self?.networkTransport = nil
            self?.mode = nil
        }
    }
}
