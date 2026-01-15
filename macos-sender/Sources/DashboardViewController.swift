import AppKit

class DashboardViewController: NSViewController {
    private var statusLabel: NSTextField!
    private var bitrateLabel: NSTextField!
    private var fpsLabel: NSTextField!
    private var resolutionLabel: NSTextField!
    private var addressLabel: NSTextField!
    private var framesLabel: NSTextField!
    private var uptimeLabel: NSTextField!
    
    private var bitrateSlider: NSSlider!
    private var fpsControl: NSSegmentedControl!
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        let titleLabel = createLabel("Virtual Display", bold: true, size: 16)
        titleLabel.frame = NSRect(x: 20, y: 360, width: 280, height: 24)
        view.addSubview(titleLabel)
        
        let statusTitle = createLabel("Status:", bold: true)
        statusTitle.frame = NSRect(x: 20, y: 320, width: 80, height: 20)
        view.addSubview(statusTitle)
        
        statusLabel = createLabel("Disconnected")
        statusLabel.frame = NSRect(x: 100, y: 320, width: 200, height: 20)
        view.addSubview(statusLabel)
        
        let addressTitle = createLabel("Pi Address:", bold: true)
        addressTitle.frame = NSRect(x: 20, y: 295, width: 80, height: 20)
        view.addSubview(addressTitle)
        
        addressLabel = createLabel("—")
        addressLabel.frame = NSRect(x: 100, y: 295, width: 200, height: 20)
        view.addSubview(addressLabel)
        
        let separator1 = createSeparator()
        separator1.frame = NSRect(x: 20, y: 280, width: 280, height: 1)
        view.addSubview(separator1)
        
        let statsTitle = createLabel("Statistics", bold: true)
        statsTitle.frame = NSRect(x: 20, y: 255, width: 280, height: 20)
        view.addSubview(statsTitle)
        
        let bitrateTitle = createLabel("Bitrate:")
        bitrateTitle.frame = NSRect(x: 30, y: 230, width: 80, height: 20)
        view.addSubview(bitrateTitle)
        
        bitrateLabel = createLabel("0.00 Mbps")
        bitrateLabel.frame = NSRect(x: 110, y: 230, width: 190, height: 20)
        view.addSubview(bitrateLabel)
        
        let fpsTitle = createLabel("FPS:")
        fpsTitle.frame = NSRect(x: 30, y: 205, width: 80, height: 20)
        view.addSubview(fpsTitle)
        
        fpsLabel = createLabel("0")
        fpsLabel.frame = NSRect(x: 110, y: 205, width: 190, height: 20)
        view.addSubview(fpsLabel)
        
        let resTitle = createLabel("Resolution:")
        resTitle.frame = NSRect(x: 30, y: 180, width: 80, height: 20)
        view.addSubview(resTitle)
        
        resolutionLabel = createLabel("1920×1080")
        resolutionLabel.frame = NSRect(x: 110, y: 180, width: 190, height: 20)
        view.addSubview(resolutionLabel)
        
        let framesTitle = createLabel("Frames:")
        framesTitle.frame = NSRect(x: 30, y: 155, width: 80, height: 20)
        view.addSubview(framesTitle)
        
        framesLabel = createLabel("0 sent / 0 dropped")
        framesLabel.frame = NSRect(x: 110, y: 155, width: 190, height: 20)
        view.addSubview(framesLabel)
        
        let uptimeTitle = createLabel("Uptime:")
        uptimeTitle.frame = NSRect(x: 30, y: 130, width: 80, height: 20)
        view.addSubview(uptimeTitle)
        
        uptimeLabel = createLabel("0:00:00")
        uptimeLabel.frame = NSRect(x: 110, y: 130, width: 190, height: 20)
        view.addSubview(uptimeLabel)
        
        let separator2 = createSeparator()
        separator2.frame = NSRect(x: 20, y: 115, width: 280, height: 1)
        view.addSubview(separator2)
        
        let settingsTitle = createLabel("Quick Settings", bold: true)
        settingsTitle.frame = NSRect(x: 20, y: 90, width: 280, height: 20)
        view.addSubview(settingsTitle)
        
        let quitButton = NSButton(frame: NSRect(x: 20, y: 20, width: 280, height: 32))
        quitButton.title = "Quit Virtual Display"
        quitButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(quitApp)
        view.addSubview(quitButton)
    }
    
    private func createLabel(_ text: String, bold: Bool = false, size: CGFloat = 13) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        label.textColor = NSColor.labelColor
        return label
    }
    
    private func createSeparator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
    
    func updateStats(_ stats: ConnectionStats) {
        guard isViewLoaded else { return }
        
        statusLabel?.stringValue = stats.piAddress != "Not connected" ? "Connected" : "Disconnected"
        statusLabel?.textColor = stats.piAddress != "Not connected" ? NSColor.systemGreen : NSColor.secondaryLabelColor
        
        bitrateLabel?.stringValue = String(format: "%.2f Mbps", stats.bitrate)
        fpsLabel?.stringValue = "\(stats.fps)"
        resolutionLabel?.stringValue = stats.resolution
        addressLabel?.stringValue = stats.piAddress
        framesLabel?.stringValue = "\(stats.encodedFrames) sent / \(stats.droppedFrames) dropped"
        
        let hours = Int(stats.uptime) / 3600
        let minutes = (Int(stats.uptime) % 3600) / 60
        let seconds = Int(stats.uptime) % 60
        uptimeLabel?.stringValue = String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
