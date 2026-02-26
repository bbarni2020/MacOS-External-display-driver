import Foundation
import Network
import Darwin

class NetworkTransport {
    private static let familyUnknown = -1
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.deskextend.network")
    private var port: UInt16 = 5900
    private var targetHost: String?
    private var reconnectTimer: Timer?
    private var isAttemptingConnection = false
    private var wiredEthernetOnly = false
    private var wifiOrEthernetOnly = false
    private var localBindAddress: String?
    private var preferredInterfaceName: String?
    
    private var bytesSent: UInt64 = 0
    private var lastStatsTime = Date()
    private var statusCallback: ((Bool, String) -> Void)?
    private var logCallback: ((String) -> Void)?
    
    var currentBitrate: Double = 0.0
    var connectedAddress: String = "Not connected"
    var canSend: Bool {
        guard let connection = connection else { return false }
        return connection.state == .ready
    }
    
    init(statusCallback: ((Bool, String) -> Void)? = nil, logCallback: ((String) -> Void)? = nil) {
        self.statusCallback = statusCallback
        self.logCallback = logCallback
    }
    
    func connect(
        to host: String,
        port: UInt16,
        wiredOnly: Bool = false,
        wifiOrEthernetOnly: Bool = false,
        localBindAddress: String? = nil,
        preferredInterfaceName: String? = nil
    ) {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            logCallback?("No address provided")
            statusCallback?(false, "Not connected")
            return
        }

        let connectionHost = resolvedHost(for: trimmed, wiredOnly: wiredOnly, preferredInterfaceName: preferredInterfaceName, localBindAddress: localBindAddress)
        targetHost = trimmed
        self.port = port
        wiredEthernetOnly = wiredOnly
        self.wifiOrEthernetOnly = wifiOrEthernetOnly
        self.localBindAddress = localBindAddress?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.preferredInterfaceName = preferredInterfaceName?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if wiredOnly {
            params.prohibitedInterfaceTypes = [.wifi, .cellular, .loopback]
            params.prohibitExpensivePaths = true
            params.prohibitConstrainedPaths = true
        } else if wifiOrEthernetOnly {
            params.prohibitedInterfaceTypes = [.cellular, .loopback]
        }
        if let bindAddress = self.localBindAddress,
           !bindAddress.isEmpty,
           shouldUseLocalBindAddress(bindAddress, forHost: connectionHost) {
            params.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(bindAddress), port: .any)
        } else if let bindAddress = self.localBindAddress, !bindAddress.isEmpty {
            logCallback?("Skipping incompatible local bind address \(bindAddress) for host \(connectionHost)")
        }
        
        let newConnection = NWConnection(host: NWEndpoint.Host(connectionHost), port: NWEndpoint.Port(integerLiteral: port), using: params)
        connection = newConnection
        if wiredOnly {
            logCallback?("Opening wired Ethernet TCP to \(connectionHost):\(port)")
        } else if wifiOrEthernetOnly {
            logCallback?("Opening Wi-Fi/Ethernet TCP to \(connectionHost):\(port)")
        } else {
            logCallback?("Opening TCP to \(connectionHost):\(port)")
        }
        
        newConnection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.isAttemptingConnection = false
                self?.connectedAddress = "\(connectionHost):\(port)"
                self?.statusCallback?(true, "\(connectionHost):\(port)")
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
                self.connect(
                    to: host,
                    port: self.port,
                    wiredOnly: self.wiredEthernetOnly,
                    wifiOrEthernetOnly: self.wifiOrEthernetOnly,
                    localBindAddress: self.localBindAddress,
                    preferredInterfaceName: self.preferredInterfaceName
                )
            }
        }
    }
    
    func send(data: Data) {
        guard let connection = connection, connection.state == .ready else { return }

        var header = UInt32(data.count).bigEndian
        let headerData = Data(bytes: &header, count: MemoryLayout<UInt32>.size)
        var packet = Data(capacity: headerData.count + data.count)
        packet.append(headerData)
        packet.append(data)

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

    private func shouldUseLocalBindAddress(_ bindAddress: String, forHost host: String) -> Bool {
        let normalizedHost = normalizeAddress(host)
        let hostFamily = ipFamily(for: normalizedHost)
        if hostFamily == Self.familyUnknown {
            return false
        }

        return isCompatibleLocalBindAddress(bindAddress, forHost: host)
    }

    private func isCompatibleLocalBindAddress(_ bindAddress: String, forHost host: String) -> Bool {
        let hostFamily = ipFamily(for: host)
        if hostFamily == Self.familyUnknown {
            return true
        }
        let bindFamily = ipFamily(for: bindAddress)
        if bindFamily == Self.familyUnknown {
            return true
        }
        return hostFamily == bindFamily
    }

    private func ipFamily(for value: String) -> Int {
        let normalized = normalizeAddress(value)
        if normalized.isEmpty {
            return Self.familyUnknown
        }

        var v4 = in_addr()
        if normalized.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 {
            return Int(AF_INET)
        }

        var v6 = in6_addr()
        if normalized.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1 {
            return Int(AF_INET6)
        }

        return Self.familyUnknown
    }

    private func normalizeAddress(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return String(trimmed.dropFirst().dropLast())
        }
        if let percent = trimmed.firstIndex(of: "%") {
            return String(trimmed[..<percent])
        }
        return trimmed
    }

    private func resolvedHost(for host: String, wiredOnly: Bool, preferredInterfaceName: String?, localBindAddress: String?) -> String {
        guard wiredOnly else { return host }
        guard host.lowercased().hasSuffix(".local") else { return host }
        guard let iface = preferredInterfaceName, !iface.isEmpty else { return host }

        let addresses = resolveAddresses(for: host)
        if addresses.isEmpty {
            return host
        }
        
        let isBindAddressV4 = localBindAddress?.contains(".") == true
        let isBindAddressV6 = localBindAddress?.contains(":") == true
        
        if isBindAddressV4, let linkLocalV4 = addresses.first(where: { $0.hasPrefix("169.254.") }) {
            return linkLocalV4
        }
        
        if isBindAddressV6, let scopedV6 = addresses.first(where: { $0.lowercased().hasPrefix("fe80:") }) {
            let strippedV6 = scopedV6.split(separator: "%").first.map(String.init) ?? scopedV6
            return "\(strippedV6)%\(iface)"
        }

        if let scopedV6 = addresses.first(where: { $0.lowercased().hasPrefix("fe80:") }) {
            let strippedV6 = scopedV6.split(separator: "%").first.map(String.init) ?? scopedV6
            return "\(strippedV6)%\(iface)"
        }
        if let linkLocalV4 = addresses.first(where: { $0.hasPrefix("169.254.") }) {
            return linkLocalV4
        }
        return host
    }

    private func resolveAddresses(for host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &result)
        guard status == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }

        var output: [String] = []
        var seen = Set<String>()
        var current: UnsafeMutablePointer<addrinfo>? = first

        while let pointer = current {
            let info = pointer.pointee
            if let sockaddr = info.ai_addr {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let rc = getnameinfo(
                    sockaddr,
                    info.ai_addrlen,
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if rc == 0 {
                    let numeric = String(cString: hostBuffer)
                    if !seen.contains(numeric) {
                        seen.insert(numeric)
                        output.append(numeric)
                    }
                }
            }
            current = info.ai_next
        }

        return output
    }
}
