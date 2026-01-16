import Foundation
import CoreGraphics

struct VirtualDisplayGeometry: Codable {
    var virtualX: Int
    var virtualY: Int
    
    var virtualWidth: Int { 1920 }
    var virtualHeight: Int { 1080 }
    
    init(virtualX: Int = 0, virtualY: Int = 2160) {
        self.virtualX = virtualX
        self.virtualY = virtualY
    }
    
    var cropRect: CGRect {
        CGRect(x: CGFloat(virtualX), y: CGFloat(virtualY), width: CGFloat(virtualWidth), height: CGFloat(virtualHeight))
    }
    
    var frame: CGRect {
        CGRect(x: CGFloat(virtualX), y: CGFloat(virtualY), width: CGFloat(virtualWidth), height: CGFloat(virtualHeight))
    }
    
    mutating func updatePosition(x: Int, y: Int) {
        self.virtualX = x
        self.virtualY = y
    }
    
    func clampedCropRect(to bounds: CGRect) -> CGRect {
        let minX = max(CGFloat(virtualX), bounds.minX)
        let minY = max(CGFloat(virtualY), bounds.minY)
        let maxX = min(CGFloat(virtualX) + CGFloat(virtualWidth), bounds.maxX)
        let maxY = min(CGFloat(virtualY) + CGFloat(virtualHeight), bounds.maxY)
        
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
    
    func transformMouseCoordinate(_ screenCoord: CGPoint) -> CGPoint {
        CGPoint(
            x: screenCoord.x - CGFloat(virtualX),
            y: screenCoord.y - CGFloat(virtualY)
        )
    }
    
    func getCropRegionFromDisplay(_ displayRect: CGRect) -> CGRect {
        let virtualWindowRect = CGRect(x: CGFloat(virtualX), y: CGFloat(virtualY), width: CGFloat(virtualWidth), height: CGFloat(virtualHeight))
        
        let intersectionX = max(0, virtualWindowRect.minX - displayRect.minX)
        let intersectionY = max(0, virtualWindowRect.minY - displayRect.minY)
        let intersectionWidth = min(virtualWindowRect.maxX - virtualWindowRect.minX, displayRect.maxX - virtualWindowRect.minX)
        let intersectionHeight = min(virtualWindowRect.maxY - virtualWindowRect.minY, displayRect.maxY - virtualWindowRect.minY)
        
        return CGRect(x: intersectionX, y: intersectionY, width: max(0, intersectionWidth), height: max(0, intersectionHeight))
    }
}
