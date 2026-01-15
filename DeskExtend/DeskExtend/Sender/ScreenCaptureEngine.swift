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
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                if let window = content.windows.first(where: { $0.windowID == UInt32(windowID) }) {
                    let filter = SCContentFilter(desktopIndependentWindow: window)
                    try await startStream(with: filter)
                } else if let display = content.displays.first {
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    try await startStream(with: filter)
                } else {
                    throw CaptureError.noDisplayFound
                }
            } catch {
                throw error
            }
        }
    }
    
    private func startStream(with filter: SCContentFilter) async throws {
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = config.width
        streamConfig.height = config.height
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        streamConfig.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        streamConfig.queueDepth = 2
        streamConfig.showsCursor = true
        streamConfig.scalesToFit = false
        streamConfig.captureResolution = .best
        streamConfig.backgroundColor = .black
        streamConfig.shouldBeOpaque = false
        
        stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        streamOutput = StreamOutput(encoder: encoder)
        
        let captureQueue = DispatchQueue(label: "com.deskextend.capture", qos: .userInteractive, attributes: [], autoreleaseFrequency: .workItem)
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream?.startCapture()
    }
    
    func stop() {
        Task {
            try? await stream?.stopCapture()
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
