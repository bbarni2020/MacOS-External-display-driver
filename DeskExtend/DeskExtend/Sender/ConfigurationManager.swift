import Foundation

final class ConfigurationManager {
    static let shared = ConfigurationManager()

    private let defaults = UserDefaults.standard
    private enum Keys {
        static let displayIndex = "DeskExtend.selectedDisplayIndex"
        static let connectionMode = "DeskExtend.connectionMode"
        static let networkHost = "DeskExtend.networkHost"
        static let networkPort = "DeskExtend.networkPort"
        static let usbDevice = "DeskExtend.usbDevice"
        static let resolution = "DeskExtend.resolution"
        static let fps = "DeskExtend.fps"
        static let bitrate = "DeskExtend.bitrate"
        static let autoConnect = "DeskExtend.autoConnect"
        static let virtualDisplayName = "DeskExtend.virtualDisplayName"
        static let virtualDisplaySize = "DeskExtend.virtualDisplaySize"
    }

    var selectedDisplayIndex: Int {
        get {
            let index = defaults.integer(forKey: Keys.displayIndex)
            return index >= 0 ? index : 0
        }
        set {
            defaults.set(newValue, forKey: Keys.displayIndex)
        }
    }

    var connectionMode: ConnectionMode {
        get {
            ConnectionMode(rawValue: defaults.string(forKey: Keys.connectionMode) ?? ConnectionMode.network.rawValue) ?? .network
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.connectionMode)
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

    var networkPort: Int {
        get {
            let port = defaults.integer(forKey: Keys.networkPort)
            return port > 0 ? port : 5900
        }
        set {
            defaults.set(newValue, forKey: Keys.networkPort)
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
            let raw = defaults.string(forKey: Keys.resolution) ?? "1920x1080"
            let parts = raw.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { return (1920, 1080) }
            return (parts[0], parts[1])
        }
        set {
            defaults.set("\(newValue.width)x\(newValue.height)", forKey: Keys.resolution)
        }
    }

    var fps: Int {
        get {
            let value = defaults.integer(forKey: Keys.fps)
            return value > 0 ? value : 30
        }
        set {
            defaults.set(newValue, forKey: Keys.fps)
        }
    }

    var bitrate: Int {
        get {
            let value = defaults.integer(forKey: Keys.bitrate)
            return value > 0 ? value : 8_000_000
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

    var virtualDisplayName: String {
        get {
            defaults.string(forKey: Keys.virtualDisplayName) ?? "YODOIT Screen"
        }
        set {
            defaults.set(newValue, forKey: Keys.virtualDisplayName)
        }
    }

    var virtualDisplaySize: (width: Int, height: Int) {
        get {
            let raw = defaults.string(forKey: Keys.virtualDisplaySize) ?? "1920x1080"
            let parts = raw.split(separator: "x").compactMap { Int($0) }
            guard parts.count == 2 else { return (1920, 1080) }
            return (parts[0], parts[1])
        }
        set {
            defaults.set("\(newValue.width)x\(newValue.height)", forKey: Keys.virtualDisplaySize)
        }
    }

    func reset() {
        defaults.removeObject(forKey: Keys.displayIndex)
        defaults.removeObject(forKey: Keys.connectionMode)
        defaults.removeObject(forKey: Keys.networkHost)
        defaults.removeObject(forKey: Keys.networkPort)
        defaults.removeObject(forKey: Keys.usbDevice)
        defaults.removeObject(forKey: Keys.resolution)
        defaults.removeObject(forKey: Keys.fps)
        defaults.removeObject(forKey: Keys.bitrate)
        defaults.removeObject(forKey: Keys.autoConnect)
        defaults.removeObject(forKey: Keys.virtualDisplayName)
        defaults.removeObject(forKey: Keys.virtualDisplaySize)
    }
}
