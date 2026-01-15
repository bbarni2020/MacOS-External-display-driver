import AppKit

class DashboardViewController: NSViewController {
    private var statusLabel: NSTextField!
    private var bitrateLabel: NSTextField!
    private var fpsLabel: NSTextField!
    private var resolutionLabel: NSTextField!
    private var addressLabel: NSTextField!
    private var addressInput: NSTextField!
    private var connectButton: NSButton!
    private var framesLabel: NSTextField!
    private var uptimeLabel: NSTextField!
    private var logTextView: NSTextView!
    
    private var bitrateSlider: NSSlider!
    private var fpsControl: NSSegmentedControl!
    
    var onConnectRequested: ((String) -> Void)?
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 520))
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
        addressTitle.frame = NSRect(x: 20, y: 345, width: 80, height: 20)
        view.addSubview(addressTitle)
        
        let addressInputContainer = NSView(frame: NSRect(x: 100, y: 325, width: 260, height: 40))
        view.addSubview(addressInputContainer)
        
        addressInput = NSTextField(frame: NSRect(x: 0, y: 20, width: 170, height: 20))
        addressInput.placeholderString = "192.168.1.100"
        addressInput.drawsBackground = true
        addressInput.backgroundColor = NSColor.textBackgroundColor
        addressInputContainer.addSubview(addressInput)
        
        connectButton = NSButton(frame: NSRect(x: 180, y: 20, width: 80, height: 20))
        connectButton.title = "Connect"
        connectButton.bezelStyle = .rounded
        connectButton.target = self
        connectButton.action = #selector(connectButtonClicked)
        addressInputContainer.addSubview(connectButton)
        
        addressLabel = createLabel("—")
        addressLabel.frame = NSRect(x: 100, y: 305, width: 260, height: 15)
        view.addSubview(addressLabel)
        
        let separator1 = createSeparator()
        separator1.frame = NSRect(x: 20, y: 285, width: 340, height: 1)
        view.addSubview(separator1)
        
        let statsTitle = createLabel("Statistics", bold: true)
        statsTitle.frame = NSRect(x: 20, y: 260, width: 340, height: 20)
        view.addSubview(statsTitle)
        
        let bitrateTitle = createLabel("Bitrate:")
        bitrateTitle.frame = NSRect(x: 30, y: 235, width: 80, height: 20)
        view.addSubview(bitrateTitle)
        
        bitrateLabel = createLabel("0.00 Mbps")
        bitrateLabel.frame = NSRect(x: 110, y: 235, width: 250, height: 20)
        view.addSubview(bitrateLabel)
        
        let fpsTitle = createLabel("FPS:")
        fpsTitle.frame = NSRect(x: 30, y: 210, width: 80, height: 20)
        view.addSubview(fpsTitle)
        
        fpsLabel = createLabel("0")
        fpsLabel.frame = NSRect(x: 110, y: 210, width: 250, height: 20)
        view.addSubview(fpsLabel)
        
        let resTitle = createLabel("Resolution:")
        resTitle.frame = NSRect(x: 30, y: 185, width: 80, height: 20)
        view.addSubview(resTitle)
        
        resolutionLabel = createLabel("1920×1080")
        resolutionLabel.frame = NSRect(x: 110, y: 185, width: 250, height: 20)
        view.addSubview(resolutionLabel)
        
        let framesTitle = createLabel("Frames:")
        framesTitle.frame = NSRect(x: 30, y: 160, width: 80, height: 20)
        view.addSubview(framesTitle)
        
        framesLabel = createLabel("0 sent / 0 dropped")
        framesLabel.frame = NSRect(x: 110, y: 160, width: 250, height: 20)
        view.addSubview(framesLabel)
        
        let uptimeTitle = createLabel("Uptime:")
        uptimeTitle.frame = NSRect(x: 30, y: 135, width: 80, height: 20)
        view.addSubview(uptimeTitle)
        
        uptimeLabel = createLabel("0:00:00")
        uptimeLabel.frame = NSRect(x: 110, y: 135, width: 250, height: 20)
        view.addSubview(uptimeLabel)
        
        let separator2 = createSeparator()
        separator2.frame = NSRect(x: 20, y: 120, width: 340, height: 1)
        view.addSubview(separator2)

        let logsTitle = createLabel("Connection Logs", bold: true)
        logsTitle.frame = NSRect(x: 20, y: 95, width: 340, height: 20)
        view.addSubview(logsTitle)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 50, width: 340, height: 60))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        logTextView = NSTextView(frame: scrollView.bounds)
        logTextView.isEditable = false
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        logTextView.textColor = NSColor.labelColor
        logTextView.backgroundColor = NSColor.textBackgroundColor
        scrollView.documentView = logTextView
        view.addSubview(scrollView)
        
        let quitButton = NSButton(frame: NSRect(x: 20, y: 10, width: 340, height: 32))
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
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            NSView.performWithoutAnimation {
                self.statusLabel?.stringValue = stats.piAddress != "Not connected" ? "Connected" : "Disconnected"
                self.statusLabel?.textColor = stats.piAddress != "Not connected" ? NSColor.systemGreen : NSColor.secondaryLabelColor
                
                self.bitrateLabel?.stringValue = String(format: "%.2f Mbps", stats.bitrate)
                self.fpsLabel?.stringValue = "\(stats.fps)"
                self.resolutionLabel?.stringValue = stats.resolution
                self.addressLabel?.stringValue = stats.piAddress
                self.framesLabel?.stringValue = "\(stats.encodedFrames) sent / \(stats.droppedFrames) dropped"
                
                let hours = Int(stats.uptime) / 3600
                let minutes = (Int(stats.uptime) % 3600) / 60
                let seconds = Int(stats.uptime) % 60
                self.uptimeLabel?.stringValue = String(format: "%d:%02d:%02d", hours, minutes, seconds)
            }
        }
    }

    func appendLog(_ text: String) {
        guard isViewLoaded else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let line = text + "\n"
            self.logTextView.textStorage?.append(NSAttributedString(string: line))
            self.logTextView.scrollToEndOfDocument(nil)
        }
    }
    
    @objc private func connectButtonClicked() {
        let address = addressInput.stringValue.trimmingCharacters(in: .whitespaces)
        if !address.isEmpty {
            onConnectRequested?(address)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
