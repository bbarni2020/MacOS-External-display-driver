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
    
    private var statsTimer: Timer?
    private var startTime = Date()

    var onConnect: ((String, Int) -> Void)?
    var onConnect60fps: ((String, Int) -> Void)?
    var onDisconnect: (() -> Void)?
    
    init() {
        setupStats()
    }
    
    func start() {
        isRunning = true
    }

    func connect(to address: String, port: Int) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appendLog("No address provided")
            return
        }
        appendLog("Connecting to \(trimmed):\(port)...")
        onConnect?(trimmed, port)
        piAddress = "\(trimmed):\(port)"
        startTime = Date()
    }
    
    func connect60fps(to address: String, port: Int) {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            appendLog("No address provided")
            return
        }
        appendLog("Connecting to \(trimmed):\(port) in 60 FPS mode...")
        onConnect60fps?(trimmed, port)
        piAddress = "\(trimmed):\(port)"
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
}
