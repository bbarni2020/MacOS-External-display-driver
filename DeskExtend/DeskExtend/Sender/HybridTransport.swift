import Foundation

final class HybridTransport {
    enum TransportMode {
        case usb(devicePath: String)
        case network(host: String, port: UInt16)
        case ethernet(host: String, port: UInt16)
        case hybrid(usbPath: String, ethernetHost: String, port: UInt16)
    }

    private var usbTransport: USBTransport?
    private var networkTransport: NetworkTransport?
    private let queue = DispatchQueue(label: "com.deskextend.hybrid")

    private var statusCallback: ((Bool, String) -> Void)?
    private var logCallback: ((String) -> Void)?
    private var mode: TransportMode?

    var currentBitrate: Double {
        let usb = usbTransport?.currentBitrate ?? 0
        let network = networkTransport?.currentBitrate ?? 0
        return max(usb, network)
    }

    var connectedAddress: String {
        switch mode {
        case .hybrid:
            if let usb = usbTransport, usb.connectedAddress != "Not connected" {
                return usb.connectedAddress
            }
            if let network = networkTransport, network.connectedAddress != "Not connected" {
                return "Ethernet: \(network.connectedAddress)"
            }
            return "Not connected"
        case .ethernet:
            if let network = networkTransport, network.connectedAddress != "Not connected" {
                return "Ethernet: \(network.connectedAddress)"
            }
            return "Not connected"
        default:
            if let usb = usbTransport, usb.connectedAddress != "Not connected" {
                return usb.connectedAddress
            }
            return networkTransport?.connectedAddress ?? "Not connected"
        }
    }

    init(statusCallback: ((Bool, String) -> Void)? = nil, logCallback: ((String) -> Void)? = nil) {
        self.statusCallback = statusCallback
        self.logCallback = logCallback
    }

    func connectUSB(devicePath: String) {
        mode = .usb(devicePath: devicePath)
        usbTransport = USBTransport(devicePath: devicePath, statusCallback: statusCallback, logCallback: logCallback)
        usbTransport?.connect()
    }

    func connectNetwork(host: String, port: UInt16, localBindAddress: String?, preferredInterfaceName: String?) {
        mode = .network(host: host, port: port)
        networkTransport = NetworkTransport(statusCallback: statusCallback, logCallback: logCallback)
        networkTransport?.connect(
            to: host,
            port: port,
            wiredOnly: false,
            wifiOrEthernetOnly: true,
            localBindAddress: localBindAddress,
            preferredInterfaceName: preferredInterfaceName
        )
    }

    func connectEthernet(host: String, port: UInt16, localBindAddress: String?, preferredInterfaceName: String?) {
        mode = .ethernet(host: host, port: port)
        networkTransport = NetworkTransport(statusCallback: statusCallback, logCallback: logCallback)
        networkTransport?.connect(
            to: host,
            port: port,
            wiredOnly: true,
            wifiOrEthernetOnly: true,
            localBindAddress: localBindAddress,
            preferredInterfaceName: preferredInterfaceName
        )
    }

    func connectHybrid(usbPath: String, ethernetHost: String, port: UInt16, ethernetLocalBindAddress: String?, ethernetInterfaceName: String?) {
        mode = .hybrid(usbPath: usbPath, ethernetHost: ethernetHost, port: port)
        usbTransport = USBTransport(devicePath: usbPath, statusCallback: { [weak self] connected, _ in
            self?.logCallback?("USB \(connected ? "connected" : "disconnected")")
        }, logCallback: logCallback)
        networkTransport = NetworkTransport(statusCallback: { [weak self] connected, _ in
            self?.logCallback?("Ethernet \(connected ? "connected" : "disconnected")")
        }, logCallback: logCallback)
        usbTransport?.connect()
        networkTransport?.connect(
            to: ethernetHost,
            port: port,
            wiredOnly: true,
            wifiOrEthernetOnly: true,
            localBindAddress: ethernetLocalBindAddress,
            preferredInterfaceName: ethernetInterfaceName
        )
    }

    func send(data: Data) {
        queue.async { [weak self] in
            if let usb = self?.usbTransport, usb.canSend {
                usb.send(data: data)
            } else if let network = self?.networkTransport, network.canSend {
                network.send(data: data)
            }
        }
    }

    func stop() {
        queue.sync {
            logCallback?("Stopping hybrid transport...")

            if let usb = usbTransport {
                usb.stop()
                logCallback?("USB transport stopped")
            }
            usbTransport = nil

            if let network = networkTransport {
                network.stop()
                logCallback?("Network transport stopped")
            }
            networkTransport = nil

            mode = nil
            statusCallback?(false, "Not connected")
            logCallback?("Hybrid transport stopped")
        }
    }
}
