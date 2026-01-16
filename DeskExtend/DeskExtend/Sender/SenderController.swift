import Foundation
import AppKit

class SenderController {
    private var transport: HybridTransport?
    private var screenCaptureEngine: ScreenCaptureEngine?
    private var videoEncoder: VideoEncoder?
    private weak var appManager: AppManager?
    private var statsTimer: Timer?
    
    init(appManager: AppManager) {
        self.appManager = appManager
    }
    
    func connect(request: ConnectionRequest) {
        stop()
        guard #available(macOS 13.0, *) else {
            appManager?.appendLog("macOS 13+ required for ScreenCaptureKit")
            return
        }
        guard let targetDisplay = DisplayManager.shared.display(at: request.displayIndex) ?? DisplayManager.shared.mainDisplay() else {
            appManager?.appendLog("Target display not found")
            return
        }
        let transport = HybridTransport(
            statusCallback: { [weak self] connected, address in
                self?.appManager?.updateConnectionStatus(
                    connected: connected,
                    address: address,
                    bitrate: self?.transport?.currentBitrate ?? 0,
                    fps: request.config.fps,
                    resolution: self?.resolutionString(for: request.config) ?? "",
                    encodedFrames: self?.videoEncoder?.frameCount ?? 0,
                    droppedFrames: self?.videoEncoder?.droppedFrames ?? 0,
                    uptime: self?.appManager?.uptime ?? 0
                )
            },
            logCallback: { [weak self] line in
                self?.appManager?.appendLog(line)
            }
        )
        self.transport = transport
        
        // Connect transport based on mode
        switch request.mode {
        case .usb:
            transport.connectUSB(devicePath: request.usbDevice)
        case .network:
            transport.connectNetwork(host: request.host, port: UInt16(request.port))
        case .hybrid:
            transport.connectHybrid(usbPath: request.usbDevice, networkHost: request.host, port: UInt16(request.port))
        }
        
        // Create video encoder
        let encoder = VideoEncoder(config: request.config) { [weak self] data in
            self?.transport?.send(data: data)
        }
        self.videoEncoder = encoder
        
        // Create screen capture engine
        let captureEngine = ScreenCaptureEngine(config: request.config, targetDisplay: targetDisplay, encoder: encoder)
        self.screenCaptureEngine = captureEngine
        
        do {
            try captureEngine.start()
            appManager?.appendLog("Screen capture started")
        } catch {
            appManager?.appendLog("Failed to start capture: \(error.localizedDescription)")
            stop()
            return
        }
        startStatsTimer()
    }
    
    func stop() {
        statsTimer?.invalidate()
        statsTimer = nil
        screenCaptureEngine = nil
        videoEncoder = nil
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
                fps: self.videoEncoder?.config.fps ?? 0,
                resolution: self.resolutionString(),
                encodedFrames: self.videoEncoder?.frameCount ?? 0,
                droppedFrames: self.videoEncoder?.droppedFrames ?? 0,
                uptime: self.appManager?.uptime ?? 0
            )
        }
    }
    
    private func resolutionString() -> String {
        guard let cfg = videoEncoder?.config else { return "" }
        return "\(cfg.width)×\(cfg.height)"
    }
    
    private func resolutionString(for config: DisplayConfig) -> String {
        return "\(config.width)×\(config.height)"
    }
}
