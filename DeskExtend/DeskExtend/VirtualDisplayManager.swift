import Foundation
import CoreGraphics

final class VirtualDisplayManager {
    private var display: CGVirtualDisplay?
    private var stream: CGDisplayStream?
    private var isActive = false

    init() {
    }

    func createDisplay(name: String, width: Int, height: Int) {
        stream?.stop()
        stream = nil
        display = nil

        let desc = CGVirtualDisplayDescriptor()
        desc.setDispatchQueue(DispatchQueue.main)
        desc.terminationHandler = { _, _ in }
        desc.name = name
        desc.maxPixelsWide = UInt32(width)
        desc.maxPixelsHigh = UInt32(height)
        desc.sizeInMillimeters = CGSize(width: 1800, height: 1012.5)
        desc.productID = 0x1235
        desc.vendorID = 0x3456
        desc.serialNum = 0x0001

        let display = CGVirtualDisplay(descriptor: desc)

        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = 2
        settings.modes = [
            CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: 60),
            CGVirtualDisplayMode(width: UInt(width), height: UInt(height), refreshRate: 30)
        ]

        self.display = display
        display.apply(settings)

        let stream = CGDisplayStream(
            dispatchQueueDisplay: display.displayID,
            outputWidth: width,
            outputHeight: height,
            pixelFormat: 1111970369,
            properties: nil,
            queue: .main,
            handler: { _, _, _, _ in }
        )

        self.stream = stream
        if let result = stream?.start(), result != .success {
            NSLog("CGDisplayStream start error: \(result)")
        }
        isActive = true
    }

    func updateDisplay(name: String, width: Int, height: Int) {
        guard isActive else { return }
        createDisplay(name: name, width: width, height: height)
    }
    
    func stop() {
        stream?.stop()
        stream = nil
        display = nil
        isActive = false
    }
}
