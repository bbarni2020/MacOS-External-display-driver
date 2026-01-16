import Foundation
import AppKit

final class DisplayInfoManager {
    static let shared = DisplayInfoManager()
    
    private(set) var availableDisplays: [String] = []
    
    init() {
        updateDisplays()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    @objc private func displayDidChange() {
        updateDisplays()
    }
    
    private func updateDisplays() {
        let screens = NSScreen.screens
        availableDisplays = screens.enumerated().map { index, screen in
            let frame = screen.frame
            let isMain = index == 0
            let mainTag = isMain ? " (Main)" : ""
            return "\(Int(frame.width))×\(Int(frame.height))\(mainTag)"
        }
    }
    
    func primaryDisplay() -> NSScreen? {
        return NSScreen.screens.first
    }
    
    func display(at index: Int) -> NSScreen? {
        guard index >= 0 && index < NSScreen.screens.count else { return nil }
        return NSScreen.screens[index]
    }
}

