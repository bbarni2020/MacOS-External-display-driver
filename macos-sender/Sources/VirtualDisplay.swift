import Foundation
import AppKit
import ScreenCaptureKit

class VirtualDisplay {
    private let config: DisplayConfig
    private let transport: NetworkTransport
    private var window: VirtualDisplayWindow?
    private var captureEngine: ScreenCaptureEngine?
    private var encoder: VideoEncoder?
    
    var currentConfig: DisplayConfig { config }
    var videoEncoder: VideoEncoder? { encoder }
    
    init(config: DisplayConfig, transport: NetworkTransport) {
        self.config = config
        self.transport = transport
    }
    
    func start() throws {
        window = VirtualDisplayWindow(config: config)
        window?.makeKeyAndOrderFront(nil)
        window?.setContentSize(NSSize(width: config.width, height: config.height))
        
        guard let windowID = window?.windowNumber else {
            throw DisplayError.windowCreationFailed
        }
        
        encoder = VideoEncoder(config: config) { [weak self] data in
            self?.transport.send(data: data)
        }
        
        captureEngine = ScreenCaptureEngine(
            config: config,
            windowID: windowID,
            encoder: encoder!
        )
        
        try captureEngine?.start()
        
        print("Capturing window \(windowID) at \(config.width)x\(config.height)")
    }
    
    func stop() {
        captureEngine?.stop()
        encoder?.stop()
        window?.close()
    }
}

enum DisplayError: Error {
    case windowCreationFailed
    case captureInitFailed
}
