import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

@available(macOS 13.0, *)
class ScreenCaptureEngine: NSObject {
    private let config: DisplayConfig
    private let windowID: Int
    private let encoder: VideoEncoder
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    
    init(config: DisplayConfig, windowID: Int, encoder: VideoEncoder) {
        self.config = config
        self.windowID = windowID
        self.encoder = encoder
        super.init()
    }
    
    func start() throws {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                
                guard let window = content.windows.first(where: { $0.windowID == UInt32(windowID) }) else {
                    print("Warning: Target window not found, capturing main display")
                    try await captureMainDisplay(content: content)
                    return
                }
                
                let filter = SCContentFilter(desktopIndependentWindow: window)
                try await startStream(with: filter)
                
            } catch {
                print("Screen capture error: \(error)")
                throw error
            }
        }
    }
    
    private func captureMainDisplay(content: SCShareableContent) async throws {
        guard let display = content.displays.first else {
            throw CaptureError.noDisplayFound
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        try await startStream(with: filter)
    }
    
    private func startStream(with filter: SCContentFilter) async throws {
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.width
        streamConfig.height = config.height
        streamConfig.minimumFrameInterval = CMTime(
            value: 1,
            timescale: CMTimeScale(config.fps)
        )
        streamConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        streamConfig.queueDepth = 3
        streamConfig.showsCursor = true
        
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        
        streamOutput = StreamOutput(encoder: encoder)
        
        try stream?.addStreamOutput(
            streamOutput!,
            type: .screen,
            sampleHandlerQueue: DispatchQueue(
                label: "com.virtualdisplay.capture",
                qos: .userInteractive
            )
        )
        
        try await stream?.startCapture()
        print("Screen capture stream started")
    }
    
    func stop() {
        Task {
            do {
                try await stream?.stopCapture()
            } catch {
                print("Error stopping capture: \(error)")
            }
        }
    }
}

@available(macOS 13.0, *)
class StreamOutput: NSObject, SCStreamOutput {
    private let encoder: VideoEncoder
    
    init(encoder: VideoEncoder) {
        self.encoder = encoder
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        encoder.encode(pixelBuffer: imageBuffer, timestamp: timestamp)
    }
}

enum CaptureError: Error {
    case noDisplayFound
    case windowNotFound
}
