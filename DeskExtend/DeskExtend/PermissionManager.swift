import Foundation
import ScreenCaptureKit
import Combine

final class PermissionManager: ObservableObject {
    @Published var hasScreenRecordingPermission = false
    @Published var permissionStatus = "Not Granted"
    @Published var showPermissionAlert = false
    
    init() {
        checkPermissions()
    }
    
    func checkPermissions() {
        Task { @MainActor in
            try? await Task.yield()
            do {
                let displays = try await SCShareableContent.current.displays
                DispatchQueue.main.async {
                    self.hasScreenRecordingPermission = !displays.isEmpty
                    self.permissionStatus = self.hasScreenRecordingPermission ? "Granted" : "Not Granted"
                }
            } catch {
                DispatchQueue.main.async {
                    self.hasScreenRecordingPermission = false
                    self.permissionStatus = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func requestPermissions() {
        showPermissionAlert = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkPermissions()
        }
    }
    
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
