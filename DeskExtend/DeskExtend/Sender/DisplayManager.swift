import Foundation
import AppKit

final class DisplayManager {
    static let shared = DisplayManager()
    private init() {}

    func allScreens() -> [NSScreen] {
        NSScreen.screens
    }

    func info(for screen: NSScreen) -> DisplayInfo {
        let frame = screen.frame
        let backing = screen.convertRectToBacking(frame)
        let index = NSScreen.screens.firstIndex(of: screen) ?? 0
        let displayName = screen.localizedName ?? (screen == NSScreen.main ? "Main Display" : "Display")
        return DisplayInfo(
            id: index,
            index: index,
            name: displayName,
            width: Int(frame.width),
            height: Int(frame.height),
            backingWidth: Int(backing.width),
            backingHeight: Int(backing.height),
            scaleFactor: screen.backingScaleFactor,
            isBuiltin: isBuiltinDisplay(screen),
            isMain: screen == NSScreen.main,
            colorSpace: screen.colorSpace?.localizedName ?? "Unknown"
        )
    }

    func displayNamed(_ name: String) -> DisplayInfo? {
        for screen in NSScreen.screens {
            let displayName = screen.localizedName ?? ""
            if displayName == name {
                return info(for: screen)
            }
        }
        return nil
    }

    func display(at index: Int) -> DisplayInfo? {
        guard index >= 0, index < NSScreen.screens.count else { return nil }
        return info(for: NSScreen.screens[index])
    }

    func mainDisplay() -> DisplayInfo? {
        guard let main = NSScreen.main else { return nil }
        return info(for: main)
    }

    private func isBuiltinDisplay(_ screen: NSScreen) -> Bool {
        let geometry = screen.frame
        let description = screen.localizedName ?? ""
        return description.lowercased().contains("built-in") || 
               (geometry.size.width > 1000 && geometry.size.height > 700)
    }
}

struct DisplayInfo {
    let id: Int
    let index: Int
    let name: String
    let width: Int
    let height: Int
    let backingWidth: Int
    let backingHeight: Int
    let scaleFactor: Double
    let isBuiltin: Bool
    let isMain: Bool
    let colorSpace: String

    var resolution: String {
        "\(width)×\(height)"
    }
}
