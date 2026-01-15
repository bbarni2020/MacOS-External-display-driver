import Foundation
import AppKit

class SenderController {
    private var transport: NetworkTransport?
    private var virtualDisplay: VirtualDisplay?
    private weak var appManager: AppManager?
    private var statsTimer: Timer?
    
    init(appManager: AppManager) {
        self.appManager = appManager
    }
    
    func connect(host: String, port: Int) {
        stop()
        guard #available(macOS 13.0, *) else {
            appManager?.appendLog("macOS 13+ required for ScreenCaptureKit")
            return
        }
        let transport = NetworkTransport(
            statusCallback: { [weak self] connected, address in
                self?.appManager?.updateConnectionStatus(
                    connected: connected,
                    address: address,
                    bitrate: self?.transport?.currentBitrate ?? 0,
                    fps: self?.virtualDisplay?.currentConfig.fps ?? 0,
                    resolution: self?.resolutionString() ?? "",
                    encodedFrames: self?.virtualDisplay?.videoEncoder?.frameCount ?? 0,
                    droppedFrames: 0,
                    uptime: self?.appManager?.uptime ?? 0
                )
            },
            logCallback: { [weak self] line in
                self?.appManager?.appendLog(line)
            }
        )
        self.transport = transport
        
        let config = DisplayConfig(width: 1920, height: 1080, fps: 30, bitrate: 8_000_000)
        let display = VirtualDisplay(config: config, transport: transport)
        virtualDisplay = display
        
        do {
            try display.start()
        } catch {
            appManager?.appendLog("Failed to start capture: \(error.localizedDescription)")
            stop()
            return
        }
        
        transport.connect(to: host, port: UInt16(port))
        startStatsTimer()
    }
    
    func connect60fps(host: String, port: Int) {
        stop()
        guard #available(macOS 13.0, *) else {
            appManager?.appendLog("macOS 13+ required for ScreenCaptureKit")
            return
        }
        let transport = NetworkTransport(
            statusCallback: { [weak self] connected, address in
                self?.appManager?.updateConnectionStatus(
                    connected: connected,
                    address: address,
                    bitrate: self?.transport?.currentBitrate ?? 0,
                    fps: self?.virtualDisplay?.currentConfig.fps ?? 0,
                    resolution: self?.resolutionString() ?? "",
                    encodedFrames: self?.virtualDisplay?.videoEncoder?.frameCount ?? 0,
                    droppedFrames: 0,
                    uptime: self?.appManager?.uptime ?? 0
                )
            },
            logCallback: { [weak self] line in
                self?.appManager?.appendLog(line)
            }
        )
        self.transport = transport
        
        let config = DisplayConfig.fullHD60
        let display = VirtualDisplay(config: config, transport: transport)
        virtualDisplay = display
        
        do {
            try display.start()
        } catch {
            appManager?.appendLog("Failed to start capture: \(error.localizedDescription)")
            stop()
            return
        }
        
        transport.connect(to: host, port: UInt16(port))
        startStatsTimer()
    }
    
    func stop() {
        statsTimer?.invalidate()
        statsTimer = nil
        virtualDisplay?.stop()
        virtualDisplay = nil
        transport?.stop()
        transport = nil
    }
    
    private func startStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.appManager?.updateConnectionStatus(
                connected: self.transport != nil,
                address: self.transport?.connectedAddress ?? "Not connected",
                bitrate: self.transport?.currentBitrate ?? 0,
                fps: self.virtualDisplay?.currentConfig.fps ?? 0,
                resolution: self.resolutionString(),
                encodedFrames: self.virtualDisplay?.videoEncoder?.frameCount ?? 0,
                droppedFrames: 0,
                uptime: self.appManager?.uptime ?? 0
            )
        }
    }
    
    private func resolutionString() -> String {
        if let cfg = virtualDisplay?.currentConfig {
            return "\(cfg.width)×\(cfg.height)"
        }
        return ""
    }
}
