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
            do {
                let displays = try await SCShareableContent.current.displays
                self.hasScreenRecordingPermission = !displays.isEmpty
                self.permissionStatus = self.hasScreenRecordingPermission ? "Granted" : "Not Granted"
            } catch {
                self.hasScreenRecordingPermission = false
                self.permissionStatus = "Error: \(error.localizedDescription)"
            }
        }
    }
    
    func requestPermissions() {
        showPermissionAlert = true
        Task { @MainActor in
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                self.hasScreenRecordingPermission = true
                self.permissionStatus = "Granted"
            } catch {
                self.hasScreenRecordingPermission = false
                self.permissionStatus = "Permission denied. Enable in System Settings > Privacy & Security > Screen Recording"
            }
        }
    }
    
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
