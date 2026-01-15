import Foundation
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate

app.run()

class AppDelegate: NSObject, NSApplicationDelegate {
    var virtualDisplay: VirtualDisplay?
    var connectionManager: ConnectionManager?
    var menuBarController: MenuBarController?
    var statsTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        menuBarController?.setup()
        
        connectionManager = ConnectionManager()
        
        menuBarController?.onConnectRequested = { [weak self] mode in
            self?.connectionManager?.connect(mode: mode)
        }
        
        menuBarController?.onDisconnectRequested = { [weak self] in
            self?.connectionManager?.disconnect()
        }
        
        if ConfigurationManager.shared.autoConnect {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.connectionManager?.connect(mode: ConfigurationManager.shared.connectionMode)
            }
        }
        
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateStats()
        }
    }
    
    private func updateStats() {
        guard let manager = connectionManager else { return }
        
        var stats = ConnectionStats()
        stats.isConnected = manager.isConnected
        stats.piAddress = manager.currentAddress
        stats.connectionMode = manager.connectionMode
        stats.diagnostics = manager.diagnosticInfo
        
        menuBarController?.stats = stats
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        statsTimer?.invalidate()
        connectionManager?.disconnect()
    }
}
