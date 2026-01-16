import Foundation
import CoreGraphics

struct DisplayConfiguration: Codable {
    var geometry: VirtualDisplayGeometry
    var isEnabled: Bool = true
    var captureDisplayIndex: Int = 0
    var targetFPS: Int = 60
    var hardwareAcceleration: Bool = true
    var lastModified: Date = Date()
    
    func save(to defaults: UserDefaults = .standard) {
        if let encoded = try? JSONEncoder().encode(self) {
            defaults.set(encoded, forKey: "virtualDisplayConfig")
            defaults.set(lastModified, forKey: "virtualDisplayConfigModified")
        }
    }
    
    static func load(from defaults: UserDefaults = .standard) -> DisplayConfiguration {
        if let data = defaults.data(forKey: "virtualDisplayConfig"),
           let decoded = try? JSONDecoder().decode(DisplayConfiguration.self, from: data) {
            return decoded
        }
        return DisplayConfiguration(geometry: VirtualDisplayGeometry())
    }
}
