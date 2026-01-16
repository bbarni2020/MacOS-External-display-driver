import Foundation
import VideoToolbox
import CoreMedia
import CoreVideo

class VideoEncoder {
    private let config: DisplayConfig
    private var compressionSession: VTCompressionSession?
    private let outputCallback: (Data) -> Void
    private let queue = DispatchQueue(label: "com.virtualdisplay.encoder")
    private(set) var frameCount: Int = 0
    private var frameDropCounter: Int = 0
    private var encodingStartTime: CFAbsoluteTime = 0
    private var spsPpsData: Data?
    private var nalUnitHeaderLength: Int = 4
    private var sentConfig: Bool = false
    
    init(config: DisplayConfig, outputCallback: @escaping (Data) -> Void) {
        self.config = config
        self.outputCallback = outputCallback
        self.encodingStartTime = CFAbsoluteTimeGetCurrent()
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
        
        VTSessionSetProperty(
            session,
            key: kVTCompressionPropertyKey_EnableLowLatencyMode,
            value: kCFBooleanTrue
        )
        
        VTCompressionSessionPrepareToEncodeFrames(session)
        
        self.compressionSession = session
    }
    
    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session = compressionSession else { 
            frameDropCounter += 1
            return 
        }
        
        let presentationTimestamp = CMTime(
            value: Int64(frameCount),
            timescale: CMTimeScale(config.fps)
        )
        
        frameCount += 1
        
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: presentationTimestamp,
            duration: .invalid,
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
        
        if status != noErr {
            frameDropCounter += 1
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
    }
    
    fileprivate func handleEncodedFrame(status: OSStatus, sampleBuffer: CMSampleBuffer) {
        guard status == noErr else {
            return
        }
        
        guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return
        }

        if spsPpsData == nil, let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) {
            var spsPointer: UnsafePointer<UInt8>?
            var spsSize: Int = 0
            var ppsPointer: UnsafePointer<UInt8>?
            var ppsSize: Int = 0
            var count: Int = 0
            var headerLength: Int = 4

            let spsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 0,
                parameterSetPointerOut: &spsPointer,
                parameterSetSizeOut: &spsSize,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &headerLength
            )

            let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                formatDesc,
                parameterSetIndex: 1,
                parameterSetPointerOut: &ppsPointer,
                parameterSetSizeOut: &ppsSize,
                parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: &headerLength
            )

            if spsStatus == noErr, ppsStatus == noErr, let sps = spsPointer, let pps = ppsPointer {
                nalUnitHeaderLength = max(1, min(4, headerLength))
                var header: [UInt8] = [0, 0, 0, 1]
                var data = Data(header)
                data.append(Data(bytes: sps, count: spsSize))
                data.append(contentsOf: header)
                data.append(Data(bytes: pps, count: ppsSize))
                spsPpsData = data
                sentConfig = false
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
        
        guard result == noErr, let pointer = dataPointer else {
            return
        }

        var bytestream = Data()
        var bufferOffset = 0
        let avccHeaderLength = nalUnitHeaderLength

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
           let first = attachments.first,
           first[kCMSampleAttachmentKey_NotSync] == nil,
           let spsPps = spsPpsData {
            bytestream.append(spsPps)
            sentConfig = true
        } else if let spsPps = spsPpsData, !sentConfig {
            bytestream.append(spsPps)
            sentConfig = true
        }

        while bufferOffset + avccHeaderLength <= length {
            var nalLength: UInt32 = 0
            memcpy(&nalLength, pointer.advanced(by: bufferOffset), avccHeaderLength)
            nalLength = CFSwapInt32BigToHost(nalLength)
            let nalSize = Int(nalLength)

            if nalSize <= 0 || bufferOffset + avccHeaderLength + nalSize > length {
                break
            }

            let startCode: [UInt8] = [0, 0, 0, 1]
            bytestream.append(contentsOf: startCode)
            bytestream.append(
                Data(bytes: pointer.advanced(by: bufferOffset + avccHeaderLength), count: nalSize)
            )

            bufferOffset += avccHeaderLength + nalSize
        }

        outputCallback(bytestream)
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
