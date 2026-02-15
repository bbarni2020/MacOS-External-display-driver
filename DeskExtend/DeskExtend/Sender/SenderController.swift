import Foundation
import AppKit

class SenderController {
    private var transport: HybridTransport?
    private var screenCaptureEngine: ScreenCaptureEngine?
    private var videoEncoder: VideoEncoder?
    private weak var appManager: AppManager?
    private var statsTimer: Timer?
    private var pendingRequest: ConnectionRequest?
    private var captureStarted = false

    init(appManager: AppManager) {
        self.appManager = appManager
    }
    
    func connect(request: ConnectionRequest) {
        stop()
        guard #available(macOS 13.0, *) else {
            appManager?.appendLog("macOS 13+ required for ScreenCaptureKit")
            return
        }
        
        pendingRequest = request
        
        let virtualName = ConfigurationManager.shared.virtualDisplayName
        let targetDisplay: DisplayInfo?
        if let vd = DisplayManager.shared.displayNamed(virtualName) {
            targetDisplay = vd
        } else if let byIndex = DisplayManager.shared.display(at: request.displayIndex) {
            targetDisplay = byIndex
        } else {
            targetDisplay = DisplayManager.shared.mainDisplay()
        }

        guard let targetDisplayUnwrapped = targetDisplay else {
            appManager?.appendLog("Target display not found")
            return
        }
        
        let transport = HybridTransport(
            statusCallback: { [weak self] connected, address in
                self?.handleConnectionStatusChange(connected: connected, address: address, request: request)
            },
            logCallback: { [weak self] line in
                self?.appManager?.appendLog(line)
            }
        )
        self.transport = transport
        
        switch request.mode {
        case .usb:
            transport.connectUSB(devicePath: request.usbDevice)
        case .network:
            transport.connectNetwork(host: request.host, port: UInt16(request.port))
        case .hybrid:
            transport.connectHybrid(usbPath: request.usbDevice, networkHost: request.host, port: UInt16(request.port))
        }
        
        let encoder = VideoEncoder(config: request.config) { [weak self] data in
            self?.transport?.send(data: data)
        }
        self.videoEncoder = encoder
        
        let captureEngine = ScreenCaptureEngine(config: request.config, targetDisplay: targetDisplayUnwrapped, encoder: encoder)
        self.screenCaptureEngine = captureEngine
    }
    
    private func handleConnectionStatusChange(connected: Bool, address: String, request: ConnectionRequest) {
        appManager?.updateConnectionStatus(
            connected: connected,
            address: address,
            bitrate: transport?.currentBitrate ?? 0,
            fps: request.config.fps,
            resolution: resolutionString(for: request.config),
            encodedFrames: videoEncoder?.frameCount ?? 0,
            droppedFrames: videoEncoder?.droppedFrames ?? 0,
            uptime: appManager?.uptime ?? 0
        )
        
        if connected && !captureStarted {
            startCapture()
        } else if !connected && captureStarted {
            stopCapture()
        }
    }
    
    private func startCapture() {
        guard let captureEngine = screenCaptureEngine else { return }
        do {
            try captureEngine.start()
            appManager?.appendLog("Screen capture started")
            captureStarted = true
            startStatsTimer()
        } catch {
            appManager?.appendLog("Failed to start capture: \(error.localizedDescription)")
            stop()
        }
    }
    
    private func stopCapture() {
        if let capture = screenCaptureEngine {
            capture.stop()
            appManager?.appendLog("Screen capture stopped")
        }
        captureStarted = false
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    func stop() {
        appManager?.appendLog("Stopping sender controller...")
        
        statsTimer?.invalidate()
        statsTimer = nil
        
        stopCapture()
        
        videoEncoder = nil
        appManager?.appendLog("Video encoder stopped")
        
        if let transport = transport {
            transport.stop()
            appManager?.appendLog("Transport stopped")
        }
        transport = nil
        
        screenCaptureEngine = nil
        pendingRequest = nil
        
        appManager?.appendLog("Sender controller stopped")
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
