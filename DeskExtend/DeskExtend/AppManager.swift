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
    
    private var statsTimer: Timer?
    private let startTime = Date()
    
    init() {
        setupStats()
    }
    
    func start() {
        isRunning = true
    }
    
    func stop() {
        isRunning = false
        isConnected = false
        piAddress = "Not connected"
    }
    
    private func setupStats() {
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    private func updateStats() {
        uptime = Date().timeIntervalSince(startTime)
    }
    
    deinit {
        statsTimer?.invalidate()
    }
}
