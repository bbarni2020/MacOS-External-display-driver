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
    private let queue = DispatchQueue(label: "com.deskextend.capture", qos: .userInteractive)
    private var isStopping = false
    
    init(config: DisplayConfig, targetDisplay: DisplayInfo, encoder: VideoEncoder) {
        self.config = config
        self.targetDisplay = targetDisplay
        self.encoder = encoder
        super.init()
    }
    
    func start() throws {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard self.targetDisplay.index >= 0 && self.targetDisplay.index < content.displays.count else {
                    throw CaptureError.noDisplayFound
                }
                let display = content.displays[self.targetDisplay.index]
                let filter = SCContentFilter(display: display, excludingWindows: [])
                try await startStream(with: filter)
            } catch {
                self.encoder.handleCaptureError(error)
            }
        }
    }
    
    private func startStream(with filter: SCContentFilter) async throws {
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.width
        streamConfig.height = config.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        streamConfig.queueDepth = 3
        streamConfig.showsCursor = true
        streamConfig.captureResolution = .automatic
        
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        streamOutput = StreamOutput(encoder: encoder)
        
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: queue)
        try await stream?.startCapture()
    }
    
    func stop() {
        guard !isStopping else { return }
        isStopping = true
        if let stream = stream {
            Task {
                do {
                    try await stream.stopCapture()
                    self.stream = nil
                    self.streamOutput = nil
                } catch {
                    self.stream = nil
                    self.streamOutput = nil
                }
                self.isStopping = false
            }
        } else {
            isStopping = false
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
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        encoder.encode(pixelBuffer: imageBuffer, timestamp: timestamp)
    }
}

enum CaptureError: Error {
    case noDisplayFound
    case windowNotFound
}
