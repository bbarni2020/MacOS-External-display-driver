import Foundation
import AppKit

class DisplayManager {
    static let shared = DisplayManager()
    
    private init() {}
    
    func getAllDisplays() -> [NSScreen] {
        return NSScreen.screens
    }
    
    func getDisplayInfo(_ screen: NSScreen) -> DisplayInfo {
        let frame = screen.frame
        let backingFrame = screen.convertRectToBacking(frame)
        
        return DisplayInfo(
            id: Int(screen.displayID),
            index: NSScreen.screens.firstIndex(of: screen) ?? 0,
            name: getDisplayName(screen.displayID),
            width: Int(frame.width),
            height: Int(frame.height),
            scaleFactor: screen.backingScaleFactor,
            isBuiltin: isBuiltinDisplay(screen.displayID),
            isMain: screen == NSScreen.main,
            colorSpace: screen.colorSpace?.localizedName ?? "Unknown"
        )
    }
    
    func getMainDisplay() -> DisplayInfo? {
        guard let main = NSScreen.main else { return nil }
        return getDisplayInfo(main)
    }
    
    func getSecondaryDisplays() -> [DisplayInfo] {
        return NSScreen.screens.dropFirst().map { getDisplayInfo($0) }
    }
    
    func getThirdDisplay() -> DisplayInfo? {
        guard NSScreen.screens.count >= 3 else { return nil }
        return getDisplayInfo(NSScreen.screens[2])
    }
    
    func getDisplayAtIndex(_ index: Int) -> DisplayInfo? {
        guard index >= 0 && index < NSScreen.screens.count else { return nil }
        return getDisplayInfo(NSScreen.screens[index])
    }
    
    private func getDisplayName(_ displayID: UInt32) -> String {
        var displayName = "Unknown"
        
        if let model = getDisplayModel(displayID) {
            displayName = model
        }
        
        if displayID == NSScreen.main?.displayID {
            displayName = "Main Display"
        }
        
        return displayName
    }
    
    private func getDisplayModel(_ displayID: UInt32) -> String? {
        var size: UInt32 = 0
        let keys = [kDisplayProductNameKey]
        
        guard let info = IODisplayCreateInfoDictionary(displayID, IOOptionBits(kIODisplayOnlyPreferredName)) as? [String: Any] else {
            return nil
        }
        
        if let names = info[kDisplayProductNameKey as String] as? [String: String],
           let name = names.values.first {
            return name
        }
        
        return nil
    }
    
    private func isBuiltinDisplay(_ displayID: UInt32) -> Bool {
        var builtIn: UInt32 = 0
        let options = IOOptionBits(kIODisplayOnlyPreferredName)
        
        guard let dict = IODisplayCreateInfoDictionary(displayID, options) as? [String: Any] else {
            return false
        }
        
        if let builtInValue = dict[kDisplayBuiltInKey] as? NSNumber {
            return builtInValue.boolValue
        }
        
        return false
    }
}

struct DisplayInfo {
    let id: Int
    let index: Int
    let name: String
    let width: Int
    let height: Int
    let scaleFactor: Double
    let isBuiltin: Bool
    let isMain: Bool
    let colorSpace: String
    
    var resolution: String {
        "\(width)×\(height)"
    }
}
