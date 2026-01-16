import Foundation
import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import Combine

@MainActor
class VirtualDisplayController: NSObject, ObservableObject {
    @Published var isRunning = false
    private var config: DisplayConfiguration
    @Published var displayGeometry: VirtualDisplayGeometry
    
    private let renderEngine = MetalRenderEngine()
    private var displayWindow: VirtualDisplayWindow?
    private var captureStream: SCStream?
    private var streamOutput: VirtualDisplayStreamOutput?
    private var inputMapper: VirtualDisplayInputMapper?
    
    private let captureQueue = DispatchQueue(label: "com.deskextend.virtualcapture", qos: .userInteractive)
    private let processQueue = DispatchQueue(label: "com.deskextend.virtualprocess", qos: .userInteractive)
    
    private var targetDisplay: SCDisplay?
    private var isStopping = false
    
    override init() {
        self.config = DisplayConfiguration.load()
        self.displayGeometry = self.config.geometry
        super.init()
    }
    
    func start() async throws {
        guard !isRunning else { return }
        
        try renderEngine.initialize()
        
        let displayConfig = DisplayConfig(width: 1920, height: 1080, fps: 60, bitrate: 10_000_000)
        DispatchQueue.main.async {
            self.displayWindow = VirtualDisplayWindow(config: displayConfig, geometry: self.displayGeometry)
            self.displayWindow?.makeKeyAndOrderFront(nil)
        }
        
        let content = try await SCShareableContent.current
        guard let display = content.displays.indices.contains(config.captureDisplayIndex) ? content.displays[config.captureDisplayIndex] : content.displays.first else {
            throw VirtualDisplayError.noDisplayAvailable
        }
        
        self.targetDisplay = display
        self.inputMapper = VirtualDisplayInputMapper(geometry: displayGeometry)
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = Int(display.width)
        streamConfig.height = Int(display.height)
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.targetFPS))
        streamConfig.showsCursor = true
        
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: nil)
        self.captureStream = stream
        
        let output = VirtualDisplayStreamOutput(
            geometry: displayGeometry,
            renderEngine: renderEngine,
            window: displayWindow
        )
        output.setDisplayRect(CGRect(x: 0, y: 0, width: display.width, height: display.height))
        self.streamOutput = output
        
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()
        
        DispatchQueue.main.async {
            self.isRunning = true
        }
    }
    
    func stop() {
        guard isRunning && !isStopping else { return }
        isStopping = true
        
        if let stream = captureStream {
            Task {
                do {
                    try await stream.stopCapture()
                    await DispatchQueue.main.run {
                        self.captureStream = nil
                        self.streamOutput = nil
                        self.displayWindow?.close()
                        self.displayWindow = nil
                        self.isRunning = false
                        self.isStopping = false
                    }
                } catch {
                    await DispatchQueue.main.run {
                        self.isRunning = false
                        self.isStopping = false
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isRunning = false
                self.isStopping = false
            }
        }
    }
    
    func updateGeometry(_ geometry: VirtualDisplayGeometry) {
        self.displayGeometry = geometry
        self.config.geometry = geometry
        self.config.save()
        self.streamOutput?.updateGeometry(geometry)
        self.inputMapper = VirtualDisplayInputMapper(geometry: geometry)
        
        DispatchQueue.main.async {
            self.displayWindow?.updatePosition(x: geometry.virtualX, y: geometry.virtualY)
        }
    }
    
    func handleMouseEvent(_ event: NSEvent) -> MouseInputEvent? {
        guard let window = displayWindow else { return nil }
        return inputMapper?.mapMouseEvent(event, window: window)
    }
    
    func handleKeyEvent(_ event: NSEvent) -> KeyboardInputEvent? {
        return inputMapper?.mapKeyEvent(event)
    }
}

extension DispatchQueue {
    func run<T>(_ block: @escaping () async -> T) async -> T {
        return await withCheckedContinuation { continuation in
            self.async {
                Task {
                    let result = await block()
                    continuation.resume(returning: result)
                }
            }
        }
    }
}

enum VirtualDisplayError: Error {
    case noDisplayAvailable
    case captureStartFailed
    case renderInitFailed
}

