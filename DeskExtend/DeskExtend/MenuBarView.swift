import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var permissionManager: PermissionManager
    @Environment(\.openWindow) private var openWindow
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                NSApplication.shared.setActivationPolicy(.regular)
                NSApplication.shared.activate(ignoringOtherApps: true)
                
                if !appManager.windowIsOpen {
                    openWindow(id: "main")
                    appManager.windowIsOpen = true
                } else {
                    if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            }) {
                HStack {
                    Image(systemName: "rectangle.on.rectangle")
                    Text("Open Dashboard")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            Divider()
            
            if appManager.isConnected {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Connected")
                            .font(.system(size: 11, weight: .medium))
                    }
                    
                    Text(appManager.piAddress)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 12) {
                        Text("\(appManager.fps) FPS")
                            .font(.system(size: 10))
                        Text(String(format: "%.1f Mbps", appManager.bitrate))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                Divider()
            }
            
            Button(action: {
                if appManager.isConnected {
                    appManager.disconnect()
                }
            }) {
                HStack {
                    Image(systemName: appManager.isConnected ? "stop.circle" : "play.circle")
                    Text(appManager.isConnected ? "Disconnect" : "Not Connected")
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .disabled(!appManager.isConnected)
            
            Divider()
            
            Button("Quit DeskExtend") {
                // Disconnect first if connected
                if appManager.isConnected {
                    appManager.disconnect()
                }
                
                // Allow termination
                if let delegate = NSApplication.shared.delegate as? AppDelegate {
                    delegate.shouldAllowTermination = true
                    delegate.virtualDisplayManager?.stop()
                }
                
                // Force immediate termination
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    exit(0)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .frame(minWidth: 200)
    }
}
