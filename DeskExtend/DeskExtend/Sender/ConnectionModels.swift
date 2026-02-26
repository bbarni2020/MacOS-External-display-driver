import Foundation

enum ConnectionMode: String, CaseIterable, Identifiable {
    case usb
    case network
    case ethernet
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usb: return "USB"
        case .network: return "Network"
        case .ethernet: return "Ethernet"
        case .hybrid: return "Hybrid"
        }
    }
}

struct ConnectionRequest {
    let mode: ConnectionMode
    let host: String
    let port: Int
    let usbDevice: String
    let ethernetInterface: String
    let ethernetBindAddress: String?
    let displayIndex: Int
    let config: DisplayConfig
}
