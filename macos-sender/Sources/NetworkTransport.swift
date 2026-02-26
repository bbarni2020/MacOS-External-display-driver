import Foundation
import Network

class NetworkTransport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.virtualdisplay.network")
    private let port: UInt16 = 5900
    
    private var bytesSent: UInt64 = 0
    private var lastStatsTime = Date()
    private var statusCallback: ((Bool, String) -> Void)?
    private var logCallback: ((String) -> Void)?
    private var targetHost: String?
    private var reconnectTimer: Timer?
    private var isAttemptingConnection = false
    private var wiredEthernetOnly = false
    private var wifiOrEthernetOnly = false
    
    private let maxInflightFrames = 30
    private var inflightFrames = 0
    private let inflightQueue = DispatchQueue(label: "com.virtualdisplay.network.inflight")
    
    var currentBitrate: Double = 0.0
    var connectedAddress: String = "Not connected"
    
    init(statusCallback: ((Bool, String) -> Void)? = nil, logCallback: ((String) -> Void)? = nil) {
        self.statusCallback = statusCallback
        self.logCallback = logCallback
    }
    
    func connect(to host: String, wiredOnly: Bool = false, wifiOrEthernetOnly: Bool = false) {
        guard !host.trimmingCharacters(in: .whitespaces).isEmpty else {
            logCallback?("No address provided")
            statusCallback?(false, "Not connected")
            return
        }

        targetHost = host
        wiredEthernetOnly = wiredOnly
        self.wifiOrEthernetOnly = wifiOrEthernetOnly
        isAttemptingConnection = true
        connection?.cancel()
        
        var tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveInterval = 10
        tcpOptions.noDelay = true
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        parameters.preferNoProxies = true
        parameters.serviceClass = .responsiveData
        if wiredOnly {
            parameters.requiredInterfaceType = .wiredEthernet
            parameters.prohibitedInterfaceTypes = [.wifi, .cellular, .loopback]
            parameters.prohibitExpensivePaths = true
            parameters.prohibitConstrainedPaths = true
        } else if wifiOrEthernetOnly {
            parameters.prohibitedInterfaceTypes = [.cellular, .loopback]
        }
        
        let newConnection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port),
            using: parameters
        )
        connection = newConnection

        if wiredOnly {
            logCallback?("Connecting to \(host):\(port) via wired Ethernet...")
        } else if wifiOrEthernetOnly {
            logCallback?("Connecting to \(host):\(port) via Wi-Fi/Ethernet...")
        } else {
            logCallback?("Connecting to \(host):\(port) via TCP...")
        }
        
        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isAttemptingConnection = false
                self?.connectedAddress = host
                self?.statusCallback?(true, host)
                self?.logCallback?("Connection established")
            case .preparing:
                self?.logCallback?("Preparing connection...")
            case .waiting(let error):
                self?.logCallback?("Waiting: \(error.localizedDescription)")
            case .failed(let error):
                self?.isAttemptingConnection = false
                self?.connection = nil
                self?.connectedAddress = "Not connected"
                self?.statusCallback?(false, "Not connected")
                self?.logCallback?("Connection failed: \(error.localizedDescription)")
                self?.scheduleReconnect()
            case .cancelled:
                self?.isAttemptingConnection = false
                self?.connection = nil
                self?.connectedAddress = "Not connected"
                self?.statusCallback?(false, "Not connected")
                self?.logCallback?("Connection cancelled")
            @unknown default:
                break
            }
        }
        
        newConnection.start(queue: queue)
    }
    
    private func scheduleReconnect() {
        guard let targetHost = targetHost else { return }
        
        DispatchQueue.main.async { [weak self] in
            self?.reconnectTimer?.invalidate()
            self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.connect(
                    to: targetHost,
                    wiredOnly: self?.wiredEthernetOnly ?? false,
                    wifiOrEthernetOnly: self?.wifiOrEthernetOnly ?? false
                )
            }
        }
    }
    
    func send(data: Data) {
        guard let connection = connection, connection.state == .ready else { 
            return 
        }

        var shouldDrop = false
        inflightQueue.sync {
            if inflightFrames >= maxInflightFrames {
                shouldDrop = true
            } else {
                inflightFrames += 1
            }
        }
        
        if shouldDrop {
            return
        }

        var header = UInt32(data.count).bigEndian
        var payload = Data(bytes: &header, count: MemoryLayout<UInt32>.size)
        payload.append(data)

        connection.send(
            content: payload,
            completion: .contentProcessed { [weak self] error in
                self?.inflightQueue.sync {
                    self?.inflightFrames -= 1
                }
                
                if let error = error {
                    self?.logCallback?("Send error: \(error.localizedDescription)")
                } else {
                    self?.updateStats(bytesSent: payload.count)
                }
            }
        )
    }
    
    private func updateStats(bytesSent: Int) {
        self.bytesSent += UInt64(bytesSent)
        
        let now = Date()
        let elapsed = now.timeIntervalSince(lastStatsTime)
        
        if elapsed >= 5.0 {
            let mbps = Double(self.bytesSent) * 8.0 / elapsed / 1_000_000.0
            currentBitrate = mbps
            self.bytesSent = 0
            lastStatsTime = now
        }
    }
    
    func stop() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        connection?.cancel()
        connection = nil
    }
}
