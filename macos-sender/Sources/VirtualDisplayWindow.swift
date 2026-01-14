import AppKit

class VirtualDisplayWindow: NSWindow {
    init(config: DisplayConfig) {
        let rect = NSRect(
            x: 0,
            y: 0,
            width: config.width,
            height: config.height
        )
        
        super.init(
            contentRect: rect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        self.title = "Virtual Display (1920×1080)"
        self.backgroundColor = NSColor(white: 0.1, alpha: 1.0)
        self.isReleasedWhenClosed = false
        
        let contentView = VirtualDisplayView(frame: rect)
        self.contentView = contentView
        
        self.center()
    }
}

class VirtualDisplayView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor(white: 0.15, alpha: 1.0).cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24),
            .foregroundColor: NSColor.white
        ]
        
        let text = "Virtual Display\nDrag windows here to show on external monitor"
        let textRect = NSRect(x: 50, y: bounds.height / 2 - 50, width: bounds.width - 100, height: 100)
        
        text.draw(in: textRect, withAttributes: attributes)
    }
}
