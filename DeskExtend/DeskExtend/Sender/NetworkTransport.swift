import Foundation
import Network

class NetworkTransport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.deskextend.network")
    private var port: UInt16 = 5900
    
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
        self.port = port
        connection?.cancel()
        
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.serviceClass = .responsiveData
        
        if let tcpOptions = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcpOptions.enableKeepalive = true
            tcpOptions.keepaliveIdle = 2
            tcpOptions.noDelay = true
        }
        
        let newConnection = NWConnection(host: NWEndpoint.Host(trimmed), port: NWEndpoint.Port(integerLiteral: port), using: params)
        connection = newConnection
        logCallback?("Opening TCP to \(trimmed):\(port)")
        
        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.connectedAddress = "\(trimmed):\(port)"
                self?.statusCallback?(true, "\(trimmed):\(port)")
                self?.logCallback?("Connection ready")
            case .preparing:
                self?.logCallback?("Preparing connection...")
            case .waiting(let error):
                self?.logCallback?("Waiting: \(error.localizedDescription)")
            case .failed(let error):
                self?.connection = nil
                self?.connectedAddress = "Not connected"
                self?.statusCallback?(false, "Not connected")
                self?.logCallback?("Failed: \(error.localizedDescription)")
            case .cancelled:
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
    
    func send(data: Data) {
        guard let connection = connection else { return }
        
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
        connection?.cancel()
        connection = nil
        connectedAddress = "Not connected"
    }
}
