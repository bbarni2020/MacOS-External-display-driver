import AppKit
import ScreenCaptureKit
import CoreVideo
import CoreMedia

class PreviewManager {
    static let shared = PreviewManager()
    private var previewTask: Task<Void, Never>?
    
    func startPreview() {
        stopPreview()
        
        previewTask = Task {
            while !Task.isCancelled {
                do {
                    try await captureAndDisplayFrame()
                    try await Task.sleep(nanoseconds: 33_333_333)
                } catch {
                    break
                }
            }
        }
    }
    
    func stopPreview() {
        previewTask?.cancel()
        previewTask = nil
    }
    
    private func captureAndDisplayFrame() async throws {
        guard let window = VirtualMonitor.shared.windowRef else { return }
        
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let scWindow = content.windows.first(where: { $0.windowID == UInt32(window.windowNumber) }) else { return }
        
        var capturedImage: NSImage?
        let semaphore = DispatchSemaphore(value: 0)
        
        let encoder = FrameCaptureEncoder { image in
            capturedImage = image
            semaphore.signal()
        }
        
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = 1920
        streamConfig.height = 1080
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        streamConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        let output = WindowStreamOutput(encoder: encoder)
        
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: DispatchQueue(label: "com.preview.capture", qos: .userInteractive))
        try await stream.startCapture()
        
        let waited = semaphore.wait(timeout: .now() + 0.5)
        try await stream.stopCapture()
        
        if waited == .timedOut || capturedImage == nil {
            return
        }
        
        DispatchQueue.main.async {
            if let image = capturedImage {
                self.displayPreview(image)
            }
        }
    }
    
    private func displayPreview(_ image: NSImage) {
        guard let screen = NSScreen.main else { return }
        
        let size = CGSize(width: 400, height: 225)
        let frame = CGRect(x: screen.frame.maxX - 450, y: screen.frame.maxY - 300, width: size.width, height: size.height)
        
        if let existingWindow = NSApplication.shared.windows.first(where: { $0.title == "Preview" }) {
            if let imageView = existingWindow.contentView as? NSImageView {
                imageView.image = image
            }
        } else {
            let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Preview"
            window.level = .floating
            
            let imageView = NSImageView(frame: CGRect(origin: .zero, size: size))
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            window.contentView = imageView
            window.makeKeyAndOrderFront(nil)
        }
    }
}

class FrameCaptureEncoder: VideoEncoder {
    private let callback: (NSImage) -> Void
    
    init(callback: @escaping (NSImage) -> Void) {
        self.callback = callback
        let config = DisplayConfig(width: 1920, height: 1080, fps: 30, bitrate: 10_000_000)
        super.init(config: config) { _ in }
    }
    
    override func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSZeroSize)
        callback(nsImage)
    }
    
    override func stop() {
    }
}
