import Foundation

class USBTransport {
    private let devicePath: String
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.virtualdisplay.usb")
    
    private var isConnected = false
    private var statusCallback: ((Bool, String) -> Void)?
    private var logCallback: ((String) -> Void)?
    
    var currentBitrate: Double = 0.0
    var connectedAddress: String = "Not connected"
    private var bytesSent: UInt64 = 0
    private var lastStatsTime = Date()
    
    init(devicePath: String, statusCallback: ((Bool, String) -> Void)? = nil, logCallback: ((String) -> Void)? = nil) {
        self.devicePath = devicePath
        self.statusCallback = statusCallback
        self.logCallback = logCallback
    }
    
    func connect() {
        queue.async { [weak self] in
            self?.performConnect()
        }
    }
    
    private func performConnect() {
        do {
            fileHandle = FileHandle(forWritingAtPath: devicePath)
            
            guard fileHandle != nil else {
                logCallback?("Cannot open device at \(devicePath)")
                statusCallback?(false, "Not connected")
                isConnected = false
                return
            }
            
            isConnected = true
            connectedAddress = "USB: \(devicePath)"
            logCallback?("Connected to USB device at \(devicePath)")
            statusCallback?(true, connectedAddress)
        }
    }
    
    func send(data: Data) {
        guard isConnected, let fileHandle = fileHandle else {
            return
        }
        
        queue.async { [weak self] in
            do {
                var packet = data
                var header = UInt32(data.count).bigEndian
                let headerData = Data(bytes: &header, count: 4)
                packet.insert(contentsOf: headerData, at: 0)
                
                try fileHandle.write(contentsOf: packet)
                self?.updateStats(bytesSent: packet.count)
            } catch {
                self?.logCallback?("USB write error: \(error)")
                self?.disconnect()
            }
        }
    }
    
    func disconnect() {
        queue.async { [weak self] in
            self?.isConnected = false
            self?.fileHandle?.closeFile()
            self?.fileHandle = nil
            self?.connectedAddress = "Not connected"
            self?.statusCallback?(false, "Not connected")
            self?.logCallback?("USB disconnected")
        }
    }
    
    private func updateStats(bytesSent: Int) {
        self.bytesSent += UInt64(bytesSent)
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastStatsTime)
        
        if elapsed >= 5.0 {
            let mbps = Double(self.bytesSent) * 8.0 / elapsed / 1_000_000.0
            currentBitrate = mbps
            self.bytesSent = 0
            lastStatsTime = now
        }
    }
    
    func stop() {
        disconnect()
    }
}

class USBDeviceDetector {
    static func findRaspberryPiDevices() -> [String] {
        var devices: [String] = []
        let fileManager = FileManager.default
        
        let devPath = "/dev"
        if let contents = try? fileManager.contentsOfDirectory(atPath: devPath) {
            for item in contents {
                if item.hasPrefix("tty.usbmodem") || item.hasPrefix("cu.usbmodem") {
                    devices.append("\(devPath)/\(item)")
                }
            }
        }
        
        return devices
    }
    
    static func findAllUSBDevices() -> [String] {
        var devices: [String] = []
        let fileManager = FileManager.default
        
        let devPath = "/dev"
        if let contents = try? fileManager.contentsOfDirectory(atPath: devPath) {
            for item in contents {
                if item.hasPrefix("tty.usb") || item.hasPrefix("cu.usb") || 
                   item.hasPrefix("tty.usbmodem") || item.hasPrefix("cu.usbmodem") {
                    devices.append("\(devPath)/\(item)")
                }
            }
        }
        
        return devices
    }
}
