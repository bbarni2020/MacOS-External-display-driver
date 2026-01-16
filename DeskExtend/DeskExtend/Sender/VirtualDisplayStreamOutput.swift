import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import MetalKit

class VirtualDisplayStreamOutput: NSObject, SCStreamOutput {
    private var geometry: VirtualDisplayGeometry
    private let renderEngine: MetalRenderEngine
    private weak var window: VirtualDisplayWindow?
    private var lastFrameTime: Double = 0
    private var displayRect: CGRect = CGRect(x: 0, y: 0, width: 3840, height: 2160)
    
    init(geometry: VirtualDisplayGeometry, renderEngine: MetalRenderEngine, window: VirtualDisplayWindow?) {
        self.geometry = geometry
        self.renderEngine = renderEngine
        self.window = window
        super.init()
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let metalView = window?.displayView() else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let frameInterval = 1.0 / 60.0
        
        if timestamp - lastFrameTime >= frameInterval {
            lastFrameTime = timestamp
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                guard let drawable = metalView.currentDrawable else { return }
                
                do {
                    let cropRegion = self.geometry.getCropRegionFromDisplay(self.displayRect)
                    try self.renderEngine.render(
                        pixelBuffer: imageBuffer,
                        cropRect: cropRegion,
                        into: drawable
                    )
                    drawable.present()
                } catch {
                    print("Render error: \(error)")
                }
            }
        }
    }
    
    func updateGeometry(_ geometry: VirtualDisplayGeometry) {
        self.geometry = geometry
    }
    
    func setDisplayRect(_ rect: CGRect) {
        self.displayRect = rect
    }
}
