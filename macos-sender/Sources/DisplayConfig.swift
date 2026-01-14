import Foundation

struct DisplayConfig {
    let width: Int
    let height: Int
    let fps: Int
    let bitrate: Int
    
    var targetFrameTime: TimeInterval {
        return 1.0 / Double(fps)
    }
}
