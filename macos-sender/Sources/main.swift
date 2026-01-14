import Foundation
import AppKit

@main
struct VirtualDisplayApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        
        let delegate = AppDelegate()
        app.delegate = delegate
        
        print("Virtual Display Sender starting...")
        print("Target resolution: 1920x1080 @ 30 FPS")
        
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var virtualDisplay: VirtualDisplay?
    var networkTransport: NetworkTransport?
    var menuBarController: MenuBarController?
    var startTime: Date?
    var statsTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        menuBarController?.setup()
        
        do {
            let config = DisplayConfig(
                width: 1920,
                height: 1080,
                fps: 30,
                bitrate: 8_000_000
            )
            
            networkTransport = NetworkTransport(statusCallback: { [weak self] connected, address in
                self?.menuBarController?.isConnected = connected
                if connected {
                    self?.startTime = Date()
                }
                self?.updateStats(piAddress: address)
            })
            try networkTransport?.start()
            
            virtualDisplay = VirtualDisplay(config: config, transport: networkTransport!)
            try virtualDisplay?.start()
            
            print("Virtual display started successfully")
            print("Listening for Pi connection on port 5900")
            
            statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateStats()
            }
        } catch {
            print("Failed to start virtual display: \(error)")
            NSApplication.shared.terminate(nil)
        }
    }
    
    private func updateStats(piAddress: String? = nil) {
        var stats = ConnectionStats()
        
        if let transport = networkTransport {
            stats.bitrate = transport.currentBitrate
            stats.piAddress = piAddress ?? (menuBarController?.isConnected == true ? transport.connectedAddress : "Not connected")
        }
        
        if let config = virtualDisplay?.config {
            stats.fps = config.fps
            stats.resolution = "\(config.width)×\(config.height)"
        }
        
        if let start = startTime {
            stats.uptime = Date().timeIntervalSince(start)
        }
        
        if let encoder = virtualDisplay?.encoder {
            stats.encodedFrames = encoder.frameCount
        }
        
        menuBarController?.stats = stats
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        statsTimer?.invalidate()
        virtualDisplay?.stop()
        networkTransport?.stop()
        print("Virtual display stopped")
    }
}
