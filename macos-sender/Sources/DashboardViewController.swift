import AppKit

class DashboardViewController: NSViewController {
    private var statusLabel: NSTextField!
    private var bitrateLabel: NSTextField!
    private var fpsLabel: NSTextField!
    private var resolutionLabel: NSTextField!
    private var addressLabel: NSTextField!
    private var addressInput: NSTextField!
    private var connectButton: NSButton!
    private var disconnectButton: NSButton!
    private var framesLabel: NSTextField!
    private var uptimeLabel: NSTextField!
    private var logTextView: NSTextView!
    private var modeSelector: NSSegmentedControl!
    private var usbDevicePopup: NSPopUpButton!
    private var usbDeviceContainer: NSView!
    private var addressInputContainer: NSView!
    
    private var bitrateSlider: NSSlider!
    private var fpsControl: NSSegmentedControl!
    
    private var networkModeClickCount = 0
    private var lastNetworkClickTime: Date?
    
    var onConnectRequested: ((String) -> Void)?
    var onDisconnectRequested: (() -> Void)?
    
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 620))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    private func setupUI() {
        let titleLabel = createLabel("Virtual Display", bold: true, size: 16)
        titleLabel.frame = NSRect(x: 20, y: 570, width: 280, height: 24)
        view.addSubview(titleLabel)
        
        let modeTitle = createLabel("Transport Mode:", bold: true)
        modeTitle.frame = NSRect(x: 20, y: 535, width: 340, height: 20)
        view.addSubview(modeTitle)
        
        modeSelector = NSSegmentedControl(frame: NSRect(x: 20, y: 510, width: 340, height: 24))
        modeSelector.segmentCount = 3
        modeSelector.setLabel("USB", forSegment: 0)
        modeSelector.setLabel("Network", forSegment: 1)
        modeSelector.setLabel("Hybrid", forSegment: 2)
        modeSelector.selectedSegment = 0
        modeSelector.target = self
        modeSelector.action = #selector(modeChanged)
        view.addSubview(modeSelector)
        
        let separator0 = createSeparator()
        separator0.frame = NSRect(x: 20, y: 490, width: 340, height: 1)
        view.addSubview(separator0)
        
        usbDeviceContainer = NSView(frame: NSRect(x: 20, y: 440, width: 340, height: 45))
        view.addSubview(usbDeviceContainer)
        
        let usbTitle = createLabel("USB Device:", bold: true)
        usbTitle.frame = NSRect(x: 0, y: 25, width: 340, height: 20)
        usbDeviceContainer.addSubview(usbTitle)
        
        usbDevicePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 340, height: 24))
        usbDevicePopup.target = self
        usbDevicePopup.action = #selector(usbDeviceSelected)
        usbDeviceContainer.addSubview(usbDevicePopup)
        
        refreshUSBDevices()
        
        addressInputContainer = NSView(frame: NSRect(x: 20, y: 390, width: 340, height: 45))
        view.addSubview(addressInputContainer)
        
        let addressTitle = createLabel("Pi Address:", bold: true)
        addressTitle.frame = NSRect(x: 0, y: 25, width: 340, height: 20)
        addressInputContainer.addSubview(addressTitle)
        
        addressInput = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 20))
        addressInput.placeholderString = "192.168.1.100"
        addressInput.drawsBackground = true
        addressInput.backgroundColor = NSColor.textBackgroundColor
        addressInputContainer.addSubview(addressInput)
        
        connectButton = NSButton(frame: NSRect(x: 265, y: 0, width: 75, height: 20))
        connectButton.title = "Connect"
        connectButton.bezelStyle = .rounded
        connectButton.target = self
        connectButton.action = #selector(connectButtonClicked)
        addressInputContainer.addSubview(connectButton)
        
        disconnectButton = NSButton(frame: NSRect(x: 265, y: 0, width: 75, height: 20))
        disconnectButton.title = "Disconnect"
        disconnectButton.bezelStyle = .rounded
        disconnectButton.target = self
        disconnectButton.action = #selector(disconnectButtonClicked)
        disconnectButton.isHidden = true
        addressInputContainer.addSubview(disconnectButton)
        
        updateUIForMode()
        
        addressLabel = createLabel("—")
        addressLabel.frame = NSRect(x: 20, y34570, width: 340, height: 15)
        view.addSubview(addressLabel)
        
        let separator1 = createSeparator()
        320, width: 80, height: 20)
        view.addSubview(bitrateTitle)
        
        bitrateLabel = createLabel("0.00 Mbps")
        bitrateLabel.frame = NSRect(x: 110, y: 320, width: 250, height: 20)
        view.addSubview(bitrateLabel)
        
        let fpsTitle = createLabel("FPS:")
        fpsTitle.frame = NSRect(x: 30, y: 295, width: 80, height: 20)
        view.addSubview(fpsTitle)
        
        fpsLabel = createLabel("0")
        fpsLabel.frame = NSRect(x: 110, y: 295, width: 250, height: 20)
        view.addSubview(fpsLabel)
        
        let resTitle = createLabel("Resolution:")
        resTitle.frame = NSRect(x: 30, y: 270, width: 80, height: 20)
        view.addSubview(resTitle)
        
        resolutionLabel = createLabel("1920×1080")
        resolutionLabel.frame = NSRect(x: 110, y: 270, width: 250, height: 20)
        view.addSubview(resolutionLabel)
        
        let framesTitle = createLabel("Frames:")
        framesTitle.frame = NSRect(x: 30, y: 245, width: 80, height: 20)
        view.addSubview(framesTitle)
        
        framesLabel = createLabel("0 sent / 0 dropped")
        framesLabel.frame = NSRect(x: 110, y: 245, width: 250, height: 20)
        view.addSubview(framesLabel)
        
        let uptimeTitle = createLabel("Uptime:")
        uptimeTitle.frame = NSRect(x: 30, y: 220, width: 80, height: 20)
        view.addSubview(uptimeTitle)
        
        uptimeLabel = createLabel("0:00:00")
        uptimeLabel.frame = NSRect(x: 110, y: 220, width: 250, height: 20)
        view.addSubview(uptimeLabel)
        
        let separator2 = createSeparator()
        separator2.frame = NSRect(x: 20, y: 205, width: 340, height: 1)
        view.addSubview(separator2)

        let logsTitle = createLabel("Connection Logs", bold: true)
        logsTitle.frame = NSRect(x: 20, y: 180, width: 340, height: 20)
        view.addSubview(logsTitle)

        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 50, width: 340, height: 125))
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        logTextView = NSTextView(frame: scrollView.bounds)
        logTextView.isEditable = false
        logTextView.font = NSFont.monospacedSystemFont(ofSize: 10
        let scrollView = NSScrollView(frame: NSRect(x: 20, y: 50, width: 340, height: 70))
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
    
    @objc private func modeChanged() {
        let selectedMode = modeSelector.selectedSegment
        
        if selectedMode == 1 {
            let now = Date()
            if let lastClick = lastNetworkClickTime, now.timeIntervalSince(lastClick) < 0.5 {
                networkModeClickCount += 1
                if networkModeClickCount >= 3 {
                    networkModeClickCount = 0
                    openTestWindow()
                    return
                }
            } else {
                networkModeClickCount = 1
            }
            lastNetworkClickTime = now
        }
        
        ConfigurationManager.shared.connectionMode = getSelectedModeString()
        updateUIForMode()
    }
    
    private func getSelectedModeString() -> String {
        switch modeSelector.selectedSegment {
        case 0: return "usb"
        case 1: return "network"
        case 2: return "hybrid"
        default: return "usb"
        }
    }
    
    private func updateUIForMode() {
        let mode = getSelectedModeString()
        
        let isUSB = (mode == "usb")
        let isNetwork = (mode == "network")
        let isHybrid = (mode == "hybrid")
        
        usbDeviceContainer.isHidden = !(isUSB || isHybrid)
        addressInputContainer.isHidden = !(isNetwork || isHybrid)
        
        if isUSB || isHybrid {
            refreshUSBDevices()
        }
    }
    
    private func refreshUSBDevices() {
        usbDevicePopup.removeAllItems()
        
        let devices = USBDeviceDetector.findAllUSBDevices()
        
        if devices.isEmpty {
            usbDevicePopup.addItem(withTitle: "No devices found")
            usbDevicePopup.isEnabled = false
        } else {
            for device in devices {
                usbDevicePopup.addItem(withTitle: device)
            }
            usbDevicePopup.isEnabled = true
            
            let saved = ConfigurationManager.shared.usbDevice
            if let index = devices.firstIndex(of: saved) {
                usbDevicePopup.selectItem(at: index)
            } else if devices.count > 0 {
                usbDevicePopup.selectItem(at: 0)
                if let selected = usbDevicePopup.selectedItem?.title {
                    ConfigurationManager.shared.usbDevice = selected
                }
            }
        }
    }
    
    @objc private func usbDeviceSelected() {
        if let selected = usbDevicePopup.selectedItem?.title {
            ConfigurationManager.shared.usbDevice = selected
            appendLog("USB device selected: \(selected)")
        }
    }
    
    private func openTestWindow() {
        let alert = NSAlert()
        alert.messageText = "Test Mode"
        alert.informativeText = "Triple-click detected. Connecting to localhost for testing."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
        
        addressInput.stringValue = "127.0.0.1"
        ConfigurationManager.shared.networkHost = "127.0.0.1"
        appendLog("Test mode activated - using localhost")
    }
    
    @objc private func connectButtonClicked() {
        let address = addressInput.stringValue.trimmingCharacters(in: .whitespaces)
        let mode = getSelectedModeString()
        
        if mode == "network" || mode == "hybrid" {
            if !address.isEmpty {
                ConfigurationManager.shared.networkHost = address
            }
        }
        
        onConnectRequested?(mode)
        connectButton.isHidden = true
        disconnectButton.isHidden = false
    }
    
    @objc private func disconnectButtonClicked() {
        onDisconnectRequested?()
        connectButton.isHidden = false
        disconnectButton.isHidden = true
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
