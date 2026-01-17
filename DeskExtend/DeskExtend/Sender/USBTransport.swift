import Foundation

final class USBTransport {
    private let devicePath: String
    private var fileHandle: FileHandle?
    private let queue = DispatchQueue(label: "com.deskextend.usb")

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
            self?.openDevice()
        }
    }

    private func openDevice() {
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
        guard isConnected, let handle = fileHandle else { return }
        queue.async { [weak self] in
            do {
                var packet = data
                var header = UInt32(data.count).bigEndian
                let headerData = Data(bytes: &header, count: 4)
                packet.insert(contentsOf: headerData, at: 0)
                try handle.write(contentsOf: packet)
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
        logCallback?("Stopping USB transport...")
        disconnect()
    }
}

enum USBDeviceDetector {
    static func raspberryPiDevices() -> [String] {
        listDevices(matching: ["tty.usbmodem", "cu.usbmodem"])
    }

    static func allDevices() -> [String] {
        listDevices(matching: ["tty.usb", "cu.usb", "tty.usbmodem", "cu.usbmodem"])
    }

    private static func listDevices(matching prefixes: [String]) -> [String] {
        let manager = FileManager.default
        let devPath = "/dev"
        guard let contents = try? manager.contentsOfDirectory(atPath: devPath) else { return [] }
        return contents.filter { item in prefixes.contains { item.hasPrefix($0) } }.map { "\(devPath)/\($0)" }
    }
}
