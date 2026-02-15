import AppKit
import Foundation

class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var dashboardController: DashboardViewController?
    
    var isConnected: Bool = false {
        didSet {
            updateIcon()
        }
    }
    
    var stats: ConnectionStats = ConnectionStats() {
        didSet {
            DispatchQueue.main.async { [weak self] in
                self?.dashboardController?.updateStats(self?.stats ?? ConnectionStats())
            }
        }
    }
    
    var onConnectRequested: ((String) -> Void)? {
        didSet {
            dashboardController?.onConnectRequested = onConnectRequested
        }
    }
    
    var onDisconnectRequested: (() -> Void)? {
        didSet {
            dashboardController?.onDisconnectRequested = onDisconnectRequested
        }
    }

    func appendLog(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.dashboardController?.appendLog(text)
        }
    }
    
    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            updateIcon()
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        
        dashboardController = DashboardViewController()
        dashboardController?.onConnectRequested = onConnectRequested
        dashboardController?.onDisconnectRequested = onDisconnectRequested
        
        popover = NSPopover()
        popover?.contentViewController = dashboardController
        popover?.behavior = .transient
    }
    
    private func updateIcon() {
        guard let button = statusItem?.button else { return }
        
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        let imageName = isConnected ? "display.triangle.fill" : "display.triangle"
        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: "Virtual Display")
        
        button.image = image?.withSymbolConfiguration(config)
        
        if isConnected {
            button.contentTintColor = NSColor.systemGreen
        } else {
            button.contentTintColor = nil
        }
    }
    
    @objc private func statusItemClicked() {
        guard let button = statusItem?.button else { return }
        
        if let popover = popover {
            if popover.isShown {
                popover.performClose(nil)
            } else {56
                popover.contentSize = NSSize(width: 380, height: 620)
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}

struct ConnectionStats {
    var bitrate: Double = 0.0
    var fps: Int = 0
    var resolution: String = "1920×1080"
    var piAddress: String = "Not connected"
    var encodedFrames: Int = 0
    var droppedFrames: Int = 0
    var uptime: TimeInterval = 0
}
