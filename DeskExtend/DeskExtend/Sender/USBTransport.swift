import Foundation
import Darwin

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
        let fd = open(devicePath, O_RDWR | O_NOCTTY)
        guard fd >= 0 else {
            let reason = String(cString: strerror(errno))
            logCallback?("Cannot open device at \(devicePath): \(reason)")
            statusCallback?(false, "Not connected")
            isConnected = false
            return
        }

        guard configureSerialDevice(fd: fd) else {
            let reason = String(cString: strerror(errno))
            close(fd)
            logCallback?("Cannot configure serial device \(devicePath): \(reason)")
            statusCallback?(false, "Not connected")
            isConnected = false
            return
        }

        fileHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        isConnected = true
        connectedAddress = "USB: \(devicePath)"
        logCallback?("Connected to USB device at \(devicePath)")
        statusCallback?(true, connectedAddress)
    }

    private func configureSerialDevice(fd: Int32) -> Bool {
        var options = termios()
        if tcgetattr(fd, &options) != 0 {
            return false
        }

        cfmakeraw(&options)
        options.c_cflag |= (CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)
        options.c_iflag = 0
        options.c_oflag = 0
        options.c_lflag = 0
        options.c_cc.16 = 0
        options.c_cc.17 = 1

        if cfsetispeed(&options, speed_t(B115200)) != 0 {
            return false
        }
        if cfsetospeed(&options, speed_t(B115200)) != 0 {
            return false
        }

        if tcsetattr(fd, TCSANOW, &options) != 0 {
            return false
        }

        _ = tcflush(fd, TCIOFLUSH)
        return true
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
    static func deskextendDevices() -> [(path: String, name: String)] {
        let devices = listModemDevices()
        var result: [(path: String, name: String)] = []
        
        for device in devices {
            if let name = extractDeviceName(device) {
                result.append((path: device, name: name))
            }
        }
        
        return result
    }
    
    static func allDevices() -> [(path: String, name: String)] {
        let devices = deskextendDevices()
        if !devices.isEmpty {
            return devices
        }
        
        return listModemDevices().map { devicePath in
            let baseName = (devicePath as NSString).lastPathComponent
            return (path: devicePath, name: "USB Accessory (\(baseName))")
        }
    }
    
    private static func listModemDevices() -> [String] {
        let manager = FileManager.default
        let devPath = "/dev"
        guard let contents = try? manager.contentsOfDirectory(atPath: devPath) else { return [] }
        let prefixes = ["cu.usbmodem", "tty.usbmodem", "cu.usbserial", "tty.usbserial", "cu.usb", "tty.usb"]
        let devices = contents
            .filter { item in prefixes.contains(where: { item.hasPrefix($0) }) }
            .map { "\(devPath)/\($0)" }
        return preferredDeviceOrder(devices)
    }

    private static func preferredDeviceOrder(_ devices: [String]) -> [String] {
        let unique = Array(Set(devices))
        return unique.sorted { left, right in
            let leftBase = (left as NSString).lastPathComponent
            let rightBase = (right as NSString).lastPathComponent
            let leftIsCallout = leftBase.hasPrefix("cu.")
            let rightIsCallout = rightBase.hasPrefix("cu.")
            if leftIsCallout != rightIsCallout {
                return leftIsCallout
            }
            return leftBase < rightBase
        }
    }
    
    private static func extractDeviceName(_ devicePath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPUSBDataType", "-xml"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]],
                  let devices = plist.first?["_items"] as? [[String: Any]] else {
                return nil
            }
            
            func searchDevices(_ items: [[String: Any]]) -> String? {
                for item in items {
                    if let manufacturer = item["manufacturer"] as? String,
                       manufacturer == "DeskExtend",
                       let serialNum = item["serial_num"] as? String {
                        if serialNum.hasPrefix("DeskExtend-") {
                            let name = String(serialNum.dropFirst("DeskExtend-".count))
                            return name.isEmpty ? "RaspberryPi" : name
                        }
                        return "RaspberryPi"
                    }
                    
                    if let children = item["_items"] as? [[String: Any]],
                       let foundName = searchDevices(children) {
                        return foundName
                    }
                }
                return nil
            }
            
            return searchDevices(devices)
        } catch {
            return nil
        }
    }
}
