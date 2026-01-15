import Foundation

class ConnectionManager: ObservableObject {
    @Published var isConnected = false
    @Published var currentAddress = "Not connected"
    @Published var connectionMode = "usb"
    @Published var diagnosticInfo = ""
    
    private var transport: HybridTransport?
    private var virtualDisplay: VirtualDisplay?
    
    func connect(mode: String) {
        let config = getDisplayConfig()
        let displayManager = DisplayManager.shared
        
        guard let targetDisplay = displayManager.getDisplayAtIndex(ConfigurationManager.shared.selectedDisplayIndex) else {
            updateDiagnostic("Target display not found")
            return
        }
        
        transport = HybridTransport(
            statusCallback: { [weak self] connected, address in
                DispatchQueue.main.async {
                    self?.isConnected = connected
                    self?.currentAddress = address
                }
            },
            logCallback: { [weak self] message in
                self?.updateDiagnostic(message)
            }
        )
        
        if #available(macOS 13.0, *) {
            do {
                virtualDisplay = try VirtualDisplay(
                    config: config,
                    transport: transport!,
                    targetDisplay: targetDisplay
                )
                try virtualDisplay?.start()
                
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
            } catch {
                updateDiagnostic("Failed to initialize: \(error)")
            }
        }
    }
    
    func disconnect() {
        virtualDisplay?.stop()
        transport?.stop()
        
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
