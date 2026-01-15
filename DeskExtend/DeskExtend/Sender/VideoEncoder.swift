import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

class VideoEncoder {
    private let config: DisplayConfig
    private var compressionSession: VTCompressionSession?
    private let outputCallback: (Data) -> Void
    private(set) var frameCount: Int = 0
    
    init(config: DisplayConfig, outputCallback: @escaping (Data) -> Void) {
        self.config = config
        self.outputCallback = outputCallback
        setupCompressionSession()
    }
    
    private func setupCompressionSession() {
        var session: VTCompressionSession?
        
        let encoderSpec: [CFString: Any] = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: true
        ]
        
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(config.width),
            height: Int32(config.height),
            codecType: kCMVideoCodecType_H264,
            encoderSpecification: encoderSpec as CFDictionary,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encodingOutputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session = session else { return }
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: config.bitrate as CFNumber)
        
        let bitrateLimit = [Double(config.bitrate) * 1.5, 1.0] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: bitrateLimit)
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: config.fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (config.fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 1 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: 0.7 as CFNumber)
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session
    }
    
    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session = compressionSession else { return }
        let pts = CMTime(value: Int64(frameCount), timescale: CMTimeScale(config.fps))
        frameCount += 1
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
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
        guard status == noErr else { return }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }
        
        var annexBData = Data()
        
        if CMSampleBufferGetNumSamples(sampleBuffer) > 0 {
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            if let attachmentsArray = attachments as? [[CFString: Any]],
               let attachment = attachmentsArray.first,
               let isKeyframe = attachment[kCMSampleAttachmentKey_NotSync] as? Bool,
               !isKeyframe {
                if let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                    var parameterSetCount: Int = 0
                    CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
                    
                    for i in 0..<parameterSetCount {
                        var parameterSetPointer: UnsafePointer<UInt8>?
                        var parameterSetSize: Int = 0
                        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(formatDescription, parameterSetIndex: i, parameterSetPointerOut: &parameterSetPointer, parameterSetSizeOut: &parameterSetSize, parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                        
                        if let pointer = parameterSetPointer {
                            annexBData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
                            annexBData.append(pointer, count: parameterSetSize)
                        }
                    }
                }
            }
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
        guard result == noErr, let pointer = dataPointer else { return }
        
        var offset = 0
        while offset < length {
            guard offset + 4 <= length else { break }
            
            let nalSizeBytes = UnsafeRawPointer(pointer.advanced(by: offset)).assumingMemoryBound(to: UInt8.self)
            let nalSize = UInt32(nalSizeBytes[0]) << 24 |
                          UInt32(nalSizeBytes[1]) << 16 |
                          UInt32(nalSizeBytes[2]) << 8 |
                          UInt32(nalSizeBytes[3])
            
            offset += 4
            
            guard offset + Int(nalSize) <= length else { break }
            
            annexBData.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            
            let nalData = UnsafeRawPointer(pointer.advanced(by: offset)).assumingMemoryBound(to: UInt8.self)
            annexBData.append(nalData, count: Int(nalSize))
            
            offset += Int(nalSize)
        }
        
        outputCallback(annexBData)
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
