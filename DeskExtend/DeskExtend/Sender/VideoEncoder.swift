import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

class VideoEncoder {
    let config: DisplayConfig
    private var compressionSession: VTCompressionSession?
    private let outputCallback: (Data) -> Void
    private(set) var frameCount: Int = 0
    private var frameDropCount: Int = 0
    private var spsPpsData: Data?
    private var nalUnitHeaderLength: Int = 4
    private var sentConfig = false
    
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
        let limit = [Double(config.bitrate) * 1.5, 1.0] as CFArray
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limit)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: config.fps as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: (config.fps * 2) as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxFrameDelayCount, value: 1 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_Quality, value: 0.7 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        compressionSession = session
    }
    
    var droppedFrames: Int {
        frameDropCount
    }
    
    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session = compressionSession else {
            frameDropCount += 1
            return
        }
        let pts = CMTime(value: Int64(frameCount), timescale: CMTimeScale(config.fps))
        frameCount += 1
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: pts,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        if status != noErr {
            frameDropCount += 1
        }
    }
    
    func stop() {
        if let session = compressionSession {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(session)
            compressionSession = nil
        }
    }
    
    func handleCaptureError(_ error: Error) {
        frameDropCount += 1
    }
    
    fileprivate func handleEncodedFrame(status: OSStatus, sampleBuffer: CMSampleBuffer) {
        guard status == noErr else { return }
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        if spsPpsData == nil, let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var parameterSetCount: Int = 0
            var headerLen: Int32 = 4
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDescription,
                parameterSetIndex: 0,
                parameterSetPointerOut: nil,
                parameterSetSizeOut: nil,
                parameterSetCountOut: &parameterSetCount,
                nalUnitHeaderLengthOut: &headerLen
            )

            var data = Data()
            for i in 0..<parameterSetCount {
                var ptr: UnsafePointer<UInt8>?
                var size: Int = 0
                CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                    formatDescription,
                    parameterSetIndex: i,
                    parameterSetPointerOut: &ptr,
                    parameterSetSizeOut: &size,
                    parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil
                )
                if let p = ptr {
                    data.append(contentsOf: [0, 0, 0, 1])
                    data.append(p, count: size)
                }
            }

            if !data.isEmpty {
                spsPpsData = data
                nalUnitHeaderLength = max(1, min(4, Int(headerLen)))
                sentConfig = false
            }
        }

        var annexBData = Data()

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first,
           first[kCMSampleAttachmentKey_NotSync] == nil,
           let sps = spsPpsData {
            annexBData.append(sps)
            sentConfig = true
        } else if let sps = spsPpsData, !sentConfig {
            annexBData.append(sps)
            sentConfig = true
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
        let header = nalUnitHeaderLength
        while offset + header <= length {
            var nalSize: UInt32 = 0
            memcpy(&nalSize, pointer.advanced(by: offset), header)
            nalSize = CFSwapInt32BigToHost(nalSize << UInt32((4 - header) * 8)) >> UInt32((4 - header) * 8)

            offset += header
            if nalSize == 0 || offset + Int(nalSize) > length { break }

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
