import Foundation
import Network

class NetworkTransport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.deskextend.network")
    private var port: UInt16 = 5900
    private var targetHost: String?
    private var reconnectTimer: Timer?
    private var isAttemptingConnection = false
    
    private var bytesSent: UInt64 = 0
    private var lastStatsTime = Date()
    private var statusCallback: ((Bool, String) -> Void)?
    private var logCallback: ((String) -> Void)?
    
    var currentBitrate: Double = 0.0
    var connectedAddress: String = "Not connected"
    
    init(statusCallback: ((Bool, String) -> Void)? = nil, logCallback: ((String) -> Void)? = nil) {
        self.statusCallback = statusCallback
        self.logCallback = logCallback
    }
    
    func connect(to host: String, port: UInt16) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            logCallback?("No address provided")
            statusCallback?(false, "Not connected")
            return
        }
        targetHost = trimmed
        self.port = port
        isAttemptingConnection = true
        reconnectTimer?.invalidate()
        connection?.cancel()
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2
        tcpOptions.noDelay = true
        
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.allowLocalEndpointReuse = true
        params.serviceClass = .responsiveData
        params.preferNoProxies = true
        
        let newConnection = NWConnection(host: NWEndpoint.Host(trimmed), port: NWEndpoint.Port(integerLiteral: port), using: params)
        connection = newConnection
        logCallback?("Opening TCP to \(trimmed):\(port)")
        
        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isAttemptingConnection = false
                self?.connectedAddress = "\(trimmed):\(port)"
                self?.statusCallback?(true, "\(trimmed):\(port)")
                self?.logCallback?("Connection ready")
            case .preparing:
                self?.logCallback?("Preparing connection...")
            case .waiting(let error):
                self?.logCallback?("Waiting: \(error.localizedDescription)")
                self?.scheduleReconnect()
            case .failed(let error):
                self?.isAttemptingConnection = false
                self?.connection = nil
                self?.connectedAddress = "Not connected"
                self?.statusCallback?(false, "Not connected")
                self?.logCallback?("Failed: \(error.localizedDescription)")
                self?.scheduleReconnect()
            case .cancelled:
                self?.isAttemptingConnection = false
                self?.connection = nil
                self?.connectedAddress = "Not connected"
                self?.statusCallback?(false, "Not connected")
                self?.logCallback?("Cancelled")
            default:
                break
            }
        }
        
        newConnection.start(queue: queue)
    }
    
    private func scheduleReconnect() {
        guard let host = targetHost, !host.isEmpty, !isAttemptingConnection else { return }
        DispatchQueue.main.async { [weak self] in
            self?.reconnectTimer?.invalidate()
            self?.reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.connect(to: host, port: self.port)
            }
        }
    }
    
    func send(data: Data) {
        guard let connection = connection, connection.state == .ready else { return }
        
        var packet = data
        var header = UInt32(data.count).bigEndian
        let headerData = Data(bytes: &header, count: 4)
        packet.insert(contentsOf: headerData, at: 0)
        
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logCallback?("Send error: \(error.localizedDescription)")
            } else {
                self?.updateStats(bytesSent: packet.count)
            }
        })
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
        isAttemptingConnection = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        targetHost = nil
        
        // Force cancel the connection
        if let conn = connection {
            conn.forceCancel()
            logCallback?("Network connection force-cancelled")
        }
        connection = nil
        
        connectedAddress = "Not connected"
        statusCallback?(false, "Not connected")
    }
}
