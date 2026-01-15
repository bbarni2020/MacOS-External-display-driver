import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo

@available(macOS 13.0, *)
class ScreenCaptureEngine: NSObject {
    private let config: DisplayConfig
    private let targetDisplay: DisplayInfo
    private let encoder: VideoEncoder
    private var stream: SCStream?
    private var streamOutput: StreamOutput?
    private let queue = DispatchQueue(label: "com.virtualdisplay.screencapture", qos: .userInteractive)
    
    init(config: DisplayConfig, targetDisplay: DisplayInfo, encoder: VideoEncoder) {
        self.config = config
        self.targetDisplay = targetDisplay
        self.encoder = encoder
        super.init()
    }
    
    func start() throws {
        queue.async { [weak self] in
            do {
                try self?.performCapture()
            } catch {
                self?.encoder.handleCaptureError(error)
            }
        }
    }
    
    private func performCapture() throws {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                
                guard let display = findTargetDisplay(in: content) else {
                    throw CaptureError.displayNotFound
                }
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                try await startStream(with: filter)
            } catch {
                throw error
            }
        }
    }
    
    private func findTargetDisplay(in content: SCShareableContent) -> SCDisplay? {
        return content.displays.first { display in
            display.displayID == UInt32(self.targetDisplay.id)
        }
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
        streamConfig.captureResolution = .automatic
        
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        
        streamOutput = StreamOutput(encoder: encoder)
        
        try stream?.addStreamOutput(
            streamOutput!,
            type: .screen,
            sampleHandlerQueue: queue
        )
        
        try await stream?.startCapture()
    }
    
    func stop() {
        Task {
            do {
                try await stream?.stopCapture()
            } catch {
                encoder.handleCaptureError(error)
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
    case displayNotFound
    case windowNotFound
}
