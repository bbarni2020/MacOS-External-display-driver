import Foundation
import Combine

final class AppManager: ObservableObject {
    @Published var isConnected = false
    @Published var piAddress = "Not connected"
    @Published var bitrate: Double = 0.0
    @Published var fps = 30
    @Published var resolution = "1920×1080"
    @Published var encodedFrames = 0
    @Published var droppedFrames = 0
    @Published var uptime: TimeInterval = 0
    @Published var isRunning = false
    @Published var showSettings = false
    @Published var windowIsOpen = false
    @Published var shouldOpenWindow = false
    @Published var logs: [String] = []
    @Published var connectionMode: ConnectionMode = ConfigurationManager.shared.connectionMode {
        didSet { ConfigurationManager.shared.connectionMode = connectionMode }
    }
    @Published var networkHost: String = ConfigurationManager.shared.networkHost {
        didSet { ConfigurationManager.shared.networkHost = networkHost }
    }
    @Published var networkPort: Int = ConfigurationManager.shared.networkPort {
        didSet { ConfigurationManager.shared.networkPort = networkPort }
    }
    @Published var usbDevice: String = ConfigurationManager.shared.usbDevice {
        didSet { ConfigurationManager.shared.usbDevice = usbDevice }
    }
    @Published var virtualDisplayName: String = ConfigurationManager.shared.virtualDisplayName {
        didSet { ConfigurationManager.shared.virtualDisplayName = virtualDisplayName }
    }
    @Published var virtualDisplayWidth: Int = ConfigurationManager.shared.virtualDisplaySize.width {
        didSet { ConfigurationManager.shared.virtualDisplaySize = (virtualDisplayWidth, virtualDisplayHeight) }
    }
    @Published var virtualDisplayHeight: Int = ConfigurationManager.shared.virtualDisplaySize.height {
        didSet { ConfigurationManager.shared.virtualDisplaySize = (virtualDisplayWidth, virtualDisplayHeight) }
    }
    @Published var selectedResolutionIndex: Int = 0 {
        didSet { persistResolution() }
    }
    @Published var selectedFpsIndex: Int = 1 {
        didSet { persistFps() }
    }
    @Published var bitrateMbps: Double = Double(ConfigurationManager.shared.bitrate) / 1_000_000.0 {
        didSet { ConfigurationManager.shared.bitrate = Int(bitrateMbps * 1_000_000) }
    }
    
    private var statsTimer: Timer?
    private var startTime = Date()

    var onConnectRequest: ((ConnectionRequest) -> Void)?
    var onDisconnect: (() -> Void)?
    weak var virtualDisplayManager: VirtualDisplayManager?
    
    private let resolutions: [(label: String, size: (Int, Int))] = [
        ("1920×1080", (1920, 1080)),
        ("1280×720", (1280, 720)),
        ("1024×768", (1024, 768))
    ]
    private let fpsOptions: [Int] = [24, 30, 60]
    
    init() {
        selectedResolutionIndex = indexForSavedResolution()
        selectedFpsIndex = indexForSavedFps()
        bitrateMbps = Double(ConfigurationManager.shared.bitrate) / 1_000_000.0
        let savedRes = ConfigurationManager.shared.resolution
        resolution = "\(savedRes.width)×\(savedRes.height)"
        fps = ConfigurationManager.shared.fps
        setupStats()
    }
    
    func start() {
        isRunning = true
    }
    
    func connect(to address: String, port: Int) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = trimmed.isEmpty ? networkHost : trimmed
        let targetPort = port > 0 ? port : networkPort
        appendLog("Connecting to \(host):\(targetPort)...")
        let config = buildConfig()
        let request = ConnectionRequest(
            mode: connectionMode,
            host: host,
            port: targetPort,
            usbDevice: usbDevice,
            displayIndex: ConfigurationManager.shared.selectedDisplayIndex,
            config: config
        )
        onConnectRequest?(request)
        piAddress = "\(host):\(targetPort)"
        networkHost = host
        networkPort = targetPort
        fps = config.fps
        resolution = configLabel(for: config)
        startTime = Date()
    }
    
    func disconnect() {
        appendLog("Disconnecting")
        onDisconnect?()
        isConnected = false
        piAddress = "Not connected"
    }
    
    func stop() {
        isRunning = false
        disconnect()
    }

    func applyVirtualDisplayConfig() {
        guard virtualDisplayWidth > 0, virtualDisplayHeight > 0 else { return }
        ConfigurationManager.shared.virtualDisplayName = virtualDisplayName
        ConfigurationManager.shared.virtualDisplaySize = (virtualDisplayWidth, virtualDisplayHeight)
        virtualDisplayManager?.updateDisplay(
            name: virtualDisplayName,
            width: virtualDisplayWidth,
            height: virtualDisplayHeight
        )
    }
    
    private func setupStats() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    private func updateStats() {
        uptime = Date().timeIntervalSince(startTime)
    }

    func updateConnectionStatus(connected: Bool, address: String, bitrate: Double, fps: Int, resolution: String, encodedFrames: Int, droppedFrames: Int, uptime: TimeInterval) {
        DispatchQueue.main.async {
            self.isConnected = connected
            self.piAddress = address
            self.bitrate = bitrate
            self.fps = fps
            self.resolution = resolution
            self.encodedFrames = encodedFrames
            self.droppedFrames = droppedFrames
            self.uptime = uptime
        }
    }

    func appendLog(_ line: String) {
        DispatchQueue.main.async {
            self.logs.append(line)
            if self.logs.count > 200 {
                self.logs.removeFirst(self.logs.count - 200)
            }
        }
    }
    
    deinit {
        statsTimer?.invalidate()
    }

    private func buildConfig() -> DisplayConfig {
        let resolution = resolutions[safe: selectedResolutionIndex]?.size ?? (1920, 1080)
        let fpsValue = fpsOptions[safe: selectedFpsIndex] ?? 30
        ConfigurationManager.shared.resolution = (resolution.0, resolution.1)
        ConfigurationManager.shared.fps = fpsValue
        ConfigurationManager.shared.bitrate = Int(bitrateMbps * 1_000_000)
        return DisplayConfig(width: resolution.0, height: resolution.1, fps: fpsValue, bitrate: Int(bitrateMbps * 1_000_000))
    }
    
    private func persistResolution() {
        let res = resolutions[safe: selectedResolutionIndex]?.size ?? (1920, 1080)
        ConfigurationManager.shared.resolution = (res.0, res.1)
        resolution = "\(res.0)×\(res.1)"
    }
    
    private func persistFps() {
        let value = fpsOptions[safe: selectedFpsIndex] ?? 30
        ConfigurationManager.shared.fps = value
        fps = value
    }
    
    private func indexForSavedResolution() -> Int {
        let saved = ConfigurationManager.shared.resolution
        if let idx = resolutions.firstIndex(where: { $0.size.0 == saved.width && $0.size.1 == saved.height }) {
            return idx
        }
        return 0
    }
    
    private func indexForSavedFps() -> Int {
        let saved = ConfigurationManager.shared.fps
        if let idx = fpsOptions.firstIndex(of: saved) {
            return idx
        }
        return 1
    }
    
    private func configLabel(for config: DisplayConfig) -> String {
        "\(config.width)×\(config.height)"
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
