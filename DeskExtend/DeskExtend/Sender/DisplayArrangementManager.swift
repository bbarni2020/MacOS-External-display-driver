import Foundation
import AppKit
import Combine

@MainActor
class DisplayArrangementManager: NSObject, ObservableObject {
    @Published var virtualDisplay: VirtualDisplayGeometry
    @Published var physicalDisplayFrame: CGRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
    @Published var selectedDisplay: String = "Main"
    
    var onGeometryChanged: ((VirtualDisplayGeometry) -> Void)?
    
    private let defaults = UserDefaults.standard
    private let geometryKey = "virtualDisplayGeometry"
    
    override init() {
        if let data = defaults.data(forKey: geometryKey),
           let decoded = try? JSONDecoder().decode(VirtualDisplayGeometry.self, from: data) {
            self.virtualDisplay = decoded
        } else {
            self.virtualDisplay = VirtualDisplayGeometry()
        }
        
        super.init()
        updatePhysicalDisplayFrame()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    func updatePosition(x: Int, y: Int) {
        virtualDisplay.updatePosition(x: x, y: y)
        persist()
        onGeometryChanged?(virtualDisplay)
    }
    
    func snapToEdge(point: CGPoint) -> VirtualDisplayGeometry {
        let snapDistance: CGFloat = 20
        var newX = virtualDisplay.virtualX
        var newY = virtualDisplay.virtualY
        
        let physicalRight = Int(physicalDisplayFrame.maxX)
        let physicalBottom = Int(physicalDisplayFrame.maxY)
        
        if abs(CGFloat(newX) - physicalDisplayFrame.minX) < snapDistance {
            newX = Int(physicalDisplayFrame.minX)
        }
        
        if abs(CGFloat(newX) + 1920 - physicalDisplayFrame.maxX) < snapDistance {
            newX = physicalRight - 1920
        }
        
        if abs(CGFloat(newY) - (physicalDisplayFrame.minY - 1080)) < snapDistance {
            newY = Int(physicalDisplayFrame.minY) - 1080
        }
        
        if abs(CGFloat(newY) + 1080 - physicalDisplayFrame.maxY) < snapDistance {
            newY = physicalBottom
        }
        
        virtualDisplay.updatePosition(x: newX, y: newY)
        persist()
        onGeometryChanged?(virtualDisplay)
        return virtualDisplay
    }
    
    @objc private func displayDidChange() {
        DispatchQueue.main.async {
            self.updatePhysicalDisplayFrame()
        }
    }
    
    private func updatePhysicalDisplayFrame() {
        if let screen = NSScreen.main {
            physicalDisplayFrame = screen.frame
        }
    }
    
    private func persist() {
        if let encoded = try? JSONEncoder().encode(virtualDisplay) {
            defaults.set(encoded, forKey: geometryKey)
        }
    }
}

