import Foundation

struct DisplayConfig {
    let width: Int
    let height: Int
    let fps: Int
    let bitrate: Int
}

struct ConnectionStats {
    var isConnected = false
    var piAddress = "Not connected"
    var connectionMode = "usb"
    var diagnostics = ""
    var resolution = "1920×1080"
    var fps = 30
    var bitrate = 8.0
    var encodedFrames = 0
    var uptime = 0.0
}
