import Foundation

enum ConnectionMode: String, CaseIterable, Identifiable {
    case usb
    case network
    case hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .usb: return "USB"
        case .network: return "Network"
        case .hybrid: return "Hybrid"
        }
    }
}

struct ConnectionRequest {
    let mode: ConnectionMode
    let host: String
    let port: Int
    let usbDevice: String
    let displayIndex: Int
    let config: DisplayConfig
}
