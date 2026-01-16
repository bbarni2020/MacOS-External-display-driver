import Foundation
import Metal
import MetalKit
import CoreVideo
import Accelerate

class MetalRenderEngine: NSObject {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    
    private let queue = DispatchQueue(label: "com.deskextend.metal", qos: .userInteractive)
    private var isInitialized = false
    
    func initialize() throws {
        guard !isInitialized else { return }
        
        try queue.sync {
            guard let device = MTLCreateSystemDefaultDevice() else {
                throw RenderError.deviceCreationFailed
            }
            
            self.device = device
            guard let commandQueue = device.makeCommandQueue() else {
                throw RenderError.commandQueueFailed
            }
            self.commandQueue = commandQueue
            
            var textureCache: CVMetalTextureCache?
            let cacheResult = CVMetalTextureCacheCreate(
                kCFAllocatorDefault,
                nil,
                device,
                nil,
                &textureCache
            )
            
            guard cacheResult == kCVReturnSuccess, let cache = textureCache else {
                throw RenderError.textureCacheFailed
            }
            
            self.textureCache = cache
            
            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
            
            try setupRenderPipeline(device: device)
            isInitialized = true
        }
    }
    
    private func setupRenderPipeline(device: MTLDevice) throws {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        struct CropData {
            float2 texCoordMin;
            float2 texCoordMax;
        };
        
        vertex VertexOut vertexShader(
            uint vertexID [[vertex_id]],
            constant CropData &cropData [[buffer(0)]]
        ) {
            float2 positions[6] = {
                float2(-1.0, -1.0), float2( 1.0, -1.0), float2(-1.0,  1.0),
                float2(-1.0,  1.0), float2( 1.0, -1.0), float2( 1.0,  1.0)
            };
            
            float2 baseTexCoords[6] = {
                float2(0.0, 1.0), float2(1.0, 1.0), float2(0.0, 0.0),
                float2(0.0, 0.0), float2(1.0, 1.0), float2(1.0, 0.0)
            };
            
            float2 minCoord = cropData.texCoordMin;
            float2 maxCoord = cropData.texCoordMax;
            
            VertexOut out;
            out.position = float4(positions[vertexID], 0.0, 1.0);
            float2 baseCoord = baseTexCoords[vertexID];
            out.texCoord = mix(minCoord, maxCoord, baseCoord);
            return out;
        }
        
        fragment float4 fragmentShader(
            VertexOut in [[stage_in]],
            texture2d<float> sourceTexture [[texture(0)]],
            sampler sourceSampler [[sampler(0)]]
        ) {
            return sourceTexture.sample(sourceSampler, in.texCoord);
        }
        """
        
        let library = try device.makeLibrary(source: shaderSource, options: nil)
        
        guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
            throw RenderError.renderEncoderFailed
        }
        
        guard let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            throw RenderError.renderEncoderFailed
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        self.pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    func render(
        pixelBuffer: CVPixelBuffer,
        cropRect: CGRect,
        into drawable: CAMetalDrawable
    ) throws {
        guard isInitialized, let commandQueue = commandQueue else {
            throw RenderError.notInitialized
        }
        
        try queue.sync {
            guard let sourceTexture = createMetalTexture(from: pixelBuffer) else {
                throw RenderError.textureCreationFailed
            }
            
            guard let commandBuffer = commandQueue.makeCommandBuffer() else {
                throw RenderError.renderEncoderFailed
            }
            
            let textureWidth = sourceTexture.width
            let textureHeight = sourceTexture.height
            let destWidth = drawable.texture.width
            let destHeight = drawable.texture.height
            
            let clampedCropX = max(0, min(Int(cropRect.minX), textureWidth - 1))
            let clampedCropY = max(0, min(Int(cropRect.minY), textureHeight - 1))
            let clampedCropWidth = max(1, min(Int(cropRect.width), textureWidth - clampedCropX))
            let clampedCropHeight = max(1, min(Int(cropRect.height), textureHeight - clampedCropY))
            
            let normalizedX = Float(clampedCropX) / Float(textureWidth)
            let normalizedY = Float(clampedCropY) / Float(textureHeight)
            let normalizedW = Float(clampedCropWidth) / Float(textureWidth)
            let normalizedH = Float(clampedCropHeight) / Float(textureHeight)
            
            let renderPassDescriptor = MTLRenderPassDescriptor()
            renderPassDescriptor.colorAttachments[0].texture = drawable.texture
            renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            renderPassDescriptor.colorAttachments[0].loadAction = .clear
            renderPassDescriptor.colorAttachments[0].storeAction = .store
            
            guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
                throw RenderError.renderEncoderFailed
            }
            
            renderEncoder.setViewport(MTLViewport(
                originX: 0, originY: 0,
                width: Double(destWidth), height: Double(destHeight),
                znear: 0, zfar: 1
            ))
            
            if let pipelineState = pipelineState {
                renderEncoder.setRenderPipelineState(pipelineState)
            }
            
            if let samplerState = samplerState {
                renderEncoder.setFragmentSamplerState(samplerState, index: 0)
            }
            
            var cropData = CropData(
                texCoordMin: SIMD2<Float>(normalizedX, normalizedY),
                texCoordMax: SIMD2<Float>(normalizedX + normalizedW, normalizedY + normalizedH)
            )
            
            renderEncoder.setVertexBytes(&cropData, length: MemoryLayout<CropData>.size, index: 0)
            renderEncoder.setFragmentTexture(sourceTexture, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            renderEncoder.endEncoding()
            
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
    
    struct CropData {
        var texCoordMin: SIMD2<Float>
        var texCoordMax: SIMD2<Float>
    }
    
    private func createMetalTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache = textureCache else { return nil }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        
        let mtlFormat: MTLPixelFormat
        switch pixelFormat {
        case kCVPixelFormatType_32BGRA:
            mtlFormat = .bgra8Unorm
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            mtlFormat = .r8Unorm
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            mtlFormat = .r8Unorm
        default:
            mtlFormat = .bgra8Unorm
        }
        
        var texture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            mtlFormat,
            width,
            height,
            0,
            &texture
        )
        
        guard result == kCVReturnSuccess, let cvTexture = texture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }
    
    enum RenderError: Error {
        case deviceCreationFailed
        case commandQueueFailed
        case textureCacheFailed
        case textureCreationFailed
        case renderEncoderFailed
        case notInitialized
    }
}
