import Foundation

class ConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var currentAddress = "Not connected"
    @Published var connectionMode = "usb"
    @Published var diagnosticInfo = ""
    
    private var transport: HybridTransport?
    private var virtualDisplay: VirtualDisplay?
    private var displayStarted = false
    private var targetDisplay: DisplayInfo?
    private var displayConfig: DisplayConfig?
    
    func connect(mode: String) {
        disconnect()
        
        let config = getDisplayConfig()
        let displayManager = DisplayManager.shared
        
        guard let display = displayManager.getDisplayAtIndex(ConfigurationManager.shared.selectedDisplayIndex) else {
            updateDiagnostic("Target display not found")
            return
        }
        
        targetDisplay = display
        displayConfig = config
        
        transport = HybridTransport(
            statusCallback: { [weak self] connected, address in
                DispatchQueue.main.async {
                    self?.handleConnectionStatus(connected: connected, address: address)
                }
            },
            logCallback: { [weak self] message in
                self?.updateDiagnostic(message)
            }
        )
        
        connectionMode = mode
        
        switch mode {
        case "usb":
            let usbPath = ConfigurationManager.shared.usbDevice
            transport?.connectUSB(devicePath: usbPath)
            updateDiagnostic("Connecting via USB: \(usbPath)")
        case "network":
            let host = ConfigurationManager.shared.networkHost
            transport?.connectNetwork(host: host)
            updateDiagnostic("Connecting via Network: \(host)")
        case "hybrid":
            let usbPath = ConfigurationManager.shared.usbDevice
            let host = ConfigurationManager.shared.networkHost
            transport?.connectHybrid(usbPath: usbPath, networkHost: host)
            updateDiagnostic("Connecting in hybrid mode")
        default:
            break
        }

        if !displayStarted {
            startDisplay()
        }
    }
    
    private func handleConnectionStatus(connected: Bool, address: String) {
        isConnected = connected
        currentAddress = address
        
        if connected && !displayStarted {
            startDisplay()
        }
    }
    
    private func startDisplay() {
        guard #available(macOS 13.0, *) else {
            updateDiagnostic("macOS 13+ required")
            return
        }
        
        guard let transport = transport, let targetDisplay = targetDisplay, let config = displayConfig else {
            return
        }
        
        do {
            virtualDisplay = try VirtualDisplay(
                config: config,
                transport: transport,
                targetDisplay: targetDisplay
            )
            try virtualDisplay?.start()
            displayStarted = true
            updateDiagnostic("Virtual display started")
        } catch {
            updateDiagnostic("Failed to start display: \(error)")
        }
    }
    
    private func stopDisplay() {
        virtualDisplay?.stop()
        virtualDisplay = nil
        displayStarted = false
        updateDiagnostic("Virtual display stopped")
    }
    
    func disconnect() {
        stopDisplay()
        transport?.stop()
        transport = nil
        
        isConnected = false
        currentAddress = "Not connected"
        updateDiagnostic("Disconnected")
    }
    
    private func getDisplayConfig() -> DisplayConfig {
        let (width, height) = ConfigurationManager.shared.resolution
        let fps = ConfigurationManager.shared.fps
        let bitrate = ConfigurationManager.shared.bitrate
        
        return DisplayConfig(
            width: width,
            height: height,
            fps: fps,
            bitrate: bitrate
        )
    }
    
    private func updateDiagnostic(_ message: String) {
        DispatchQueue.main.async {
            let timestamp = ISO8601DateFormatter().string(from: Date())
            self.diagnosticInfo = "[\(timestamp)] \(message)\n\(self.diagnosticInfo)".prefix(500).description
        }
    }
}
