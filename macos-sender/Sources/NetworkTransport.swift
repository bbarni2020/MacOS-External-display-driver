import Foundation
import Network

class NetworkTransport {
    private var listener: NWListener?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.virtualdisplay.network")
    private let port: UInt16 = 5900
    
    private var bytesSent: UInt64 = 0
    private var lastStatsTime = Date()
    private var statusCallback: ((Bool, String) -> Void)?
    
    var currentBitrate: Double = 0.0
    var connectedAddress: String = "Not connected"
    
    init(statusCallback: ((Bool, String) -> Void)? = nil) {
        self.statusCallback = statusCallback
    }
    
    func start() throws {
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))
        
        listener?.newConnectionHandler = { [weak self] newConnection in
            self?.handleNewConnection(newConnection)
        }
        
        listener?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Network listener ready on port \(self.port)")
            case .failed(let error):
                print("Listener failed: \(error)")
            default:
                break
            }
        }
        
        listener?.start(queue: queue)
    }
    
    private func handleNewConnection(_ newConnection: NWConnection) {
        connection?.cancel()
        
        connection = newConnection
        connection?.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let endpoint = newConnection.currentPath?.remoteEndpoint {
                    print("Pi connected: \(endpoint)")
                    let address = "\(endpoint)"
                    self?.connectedAddress = address
                    self?.statusCallback?(true, address)
                }
            case .failed(let error):
                print("Connection failed: \(error)")
                self?.connection = nil
                self?.connectedAddress = "Not connected"
                self?.statusCallback?(false, "Not connected")
            case .cancelled:
                self?.connection = nil
                self?.connectedAddress = "Not connected"
                self?.statusCallback?(false, "Not connected")
            default:
                break
            }
        }
        
        connection?.start(queue: queue)
    }
    
    func send(data: Data) {
        guard let connection = connection else { return }
        
        var packet = data
        var header = UInt32(data.count).bigEndian
        let headerData = Data(bytes: &header, count: 4)
        packet.insert(contentsOf: headerData, at: 0)
        
        connection.send(
            content: packet,
            completion: .contentProcessed { [weak self] error in
                if let error = error {
                    print("Send error: \(error)")
                } else {
                    self?.updateStats(bytesSent: packet.count)
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
            print(String(format: "Streaming at %.2f Mbps", mbps))
            self.currentBitrate = mbps
            self.bytesSent = 0
            lastStatsTime = now
        }
    }
    
    func stop() {
        connection?.cancel()
        listener?.cancel()
    }
}
