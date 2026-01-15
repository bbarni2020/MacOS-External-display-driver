import Foundation

class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private let defaults = UserDefaults.standard
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private enum Keys {
        static let displayIndex = "DeskExtend.selectedDisplayIndex"
        static let connectionMode = "DeskExtend.connectionMode"
        static let networkHost = "DeskExtend.networkHost"
        static let usbDevice = "DeskExtend.usbDevice"
        static let resolution = "DeskExtend.resolution"
        static let fps = "DeskExtend.fps"
        static let bitrate = "DeskExtend.bitrate"
        static let autoConnect = "DeskExtend.autoConnect"
    }
    
    var selectedDisplayIndex: Int {
        get {
            let index = defaults.integer(forKey: Keys.displayIndex)
            return index > 0 ? index : 2
        }
        set {
            defaults.set(newValue, forKey: Keys.displayIndex)
        }
    }
    
    var connectionMode: String {
        get {
            defaults.string(forKey: Keys.connectionMode) ?? "usb"
        }
        set {
            defaults.set(newValue, forKey: Keys.connectionMode)
        }
    }
    
    var networkHost: String {
        get {
            defaults.string(forKey: Keys.networkHost) ?? "192.168.1.100"
        }
        set {
            defaults.set(newValue, forKey: Keys.networkHost)
        }
    }
    
    var usbDevice: String {
        get {
            defaults.string(forKey: Keys.usbDevice) ?? "/dev/cu.usbmodem14101"
        }
        set {
            defaults.set(newValue, forKey: Keys.usbDevice)
        }
    }
    
    var resolution: (width: Int, height: Int) {
        get {
            let res = defaults.string(forKey: Keys.resolution) ?? "1920x1080"
            let parts = res.split(separator: "x").map { Int($0) ?? 0 }
            return (parts.count >= 2 ? parts[0] : 1920, parts.count >= 2 ? parts[1] : 1080)
        }
        set {
            defaults.set("\(newValue.width)x\(newValue.height)", forKey: Keys.resolution)
        }
    }
    
    var fps: Int {
        get {
            let fps = defaults.integer(forKey: Keys.fps)
            return fps > 0 ? fps : 30
        }
        set {
            defaults.set(newValue, forKey: Keys.fps)
        }
    }
    
    var bitrate: Int {
        get {
            let bitrate = defaults.integer(forKey: Keys.bitrate)
            return bitrate > 0 ? bitrate : 8_000_000
        }
        set {
            defaults.set(newValue, forKey: Keys.bitrate)
        }
    }
    
    var autoConnect: Bool {
        get {
            defaults.bool(forKey: Keys.autoConnect)
        }
        set {
            defaults.set(newValue, forKey: Keys.autoConnect)
        }
    }
    
    func reset() {
        defaults.removeObject(forKey: Keys.displayIndex)
        defaults.removeObject(forKey: Keys.connectionMode)
        defaults.removeObject(forKey: Keys.networkHost)
        defaults.removeObject(forKey: Keys.usbDevice)
        defaults.removeObject(forKey: Keys.resolution)
        defaults.removeObject(forKey: Keys.fps)
        defaults.removeObject(forKey: Keys.bitrate)
        defaults.removeObject(forKey: Keys.autoConnect)
    }
}
