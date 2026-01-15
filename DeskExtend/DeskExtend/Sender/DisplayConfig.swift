import Foundation

struct DisplayConfig {
    let width: Int
    let height: Int
    let fps: Int
    let bitrate: Int
    
    var targetFrameTime: TimeInterval {
        1.0 / Double(fps)
    }
    
    static var fullHD60: DisplayConfig {
        DisplayConfig(width: 1920, height: 1080, fps: 60, bitrate: 20_000_000)
    }
    
    static var fullHD30: DisplayConfig {
        DisplayConfig(width: 1920, height: 1080, fps: 30, bitrate: 10_000_000)
    }
}
