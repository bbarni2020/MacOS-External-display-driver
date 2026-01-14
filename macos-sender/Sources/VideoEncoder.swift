import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

class VideoEncoder {
    private let config: DisplayConfig
    private var compressionSession: VTCompressionSession?
    private let outputCallback: (Data) -> Void
    private var frameCount: Int64 = 0
    
    init(config: DisplayConfig, outputCallback: @escaping (Data) -> Void) {
        self.config = config
        self.outputCallback = outputCallback
        setupCompressionSession()
    }
    
    private func setupCompressionSession() {
        var session: VTCompressionSession?
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width),
            height: Int32(config.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encodingOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let session = session else {
            print("Failed to create compression session: \(status)")
            return
        }
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_RealTime,
            value: kCFBooleanTrue
        )
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_H264_Main_AutoLevel
        )
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AverageBitRate,
            value: config.bitrate as CFNumber
        )
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_ExpectedFrameRate,
            value: config.fps as CFNumber
        )
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
            value: (config.fps * 2) as CFNumber
        )
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_AllowFrameReordering,
            value: kCFBooleanFalse
        )
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        self.compressionSession = session
        print("Encoder initialized: H.264, \(config.bitrate / 1_000_000) Mbps")
    }
    
    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session = compressionSession else { return }
        
        let presentationTimestamp = CMTime(
            value: frameCount,
            timescale: CMTimeScale(config.fps)
        )
        
        frameCount += 1
        
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimestamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }
    
    func stop() {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
    
    fileprivate func handleEncodedFrame(status: OSStatus, sampleBuffer: CMSampleBuffer) {
        guard status == noErr else {
            print("Encoding error: \(status)")
            return
        }
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }
        
        var length: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        let result = CMBlockBufferGetDataPointer(
            dataBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )
        
        guard result == noErr, let pointer = dataPointer else {
            return
        }
        
        let data = Data(bytes: pointer, count: length)
        outputCallback(data)
    }
}

private let encodingOutputCallback: VTCompressionOutputCallback = { (
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) in
    guard let sampleBuffer = sampleBuffer else { return }
    
    let encoder = Unmanaged<VideoEncoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
    encoder.handleEncodedFrame(status: status, sampleBuffer: sampleBuffer)
}
