import AppKit
import MetalKit
import CoreVideo

class VirtualDisplayWindow: NSWindow {
    private var geometry: VirtualDisplayGeometry
    private var metalView: MTKView?
    
    init(config: DisplayConfig, geometry: VirtualDisplayGeometry) {
        self.geometry = geometry
        let rect = NSRect(x: CGFloat(geometry.virtualX), y: CGFloat(geometry.virtualY), width: CGFloat(config.width), height: CGFloat(config.height))
        super.init(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        title = ""
        level = .screenSaver
        isReleasedWhenClosed = false
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        
        guard let device = MTLCreateSystemDefaultDevice() else {
            let contentView = NSView(frame: rect)
            self.contentView = contentView
            return
        }
        
        let metalView = MTKView(frame: CGRect(x: 0, y: 0, width: config.width, height: config.height), device: device)
        metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        metalView.enableSetNeedsDisplay = true
        self.metalView = metalView
        self.contentView = metalView
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    func updatePosition(x: Int, y: Int) {
        geometry.updatePosition(x: x, y: y)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            var frame = self.frame
            frame.origin.x = CGFloat(x)
            frame.origin.y = CGFloat(y)
            self.setFrame(frame, display: true, animate: false)
        }
    }
    
    func getGeometry() -> VirtualDisplayGeometry {
        return geometry
    }
    
    func displayView() -> MTKView? {
        return metalView
    }
}
