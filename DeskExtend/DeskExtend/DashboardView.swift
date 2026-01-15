import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                HeaderView()
                    .environmentObject(appManager)
                
                TabView(selection: $selectedTab) {
                    DashboardTabView()
                        .environmentObject(appManager)
                        .environmentObject(permissionManager)
                        .tabItem {
                            Label("Dashboard", systemImage: "square.grid.2x2")
                        }
                        .tag(0)
                    
                    SettingsTabView()
                        .environmentObject(appManager)
                        .environmentObject(permissionManager)
                        .tabItem {
                            Label("Settings", systemImage: "gear")
                        }
                        .tag(1)
                    
                    ConnectionTabView()
                        .environmentObject(appManager)
                        .tabItem {
                            Label("Connection", systemImage: "wifi")
                        }
                        .tag(2)
                }
                .padding()
            }
        }
        .onAppear {
            permissionManager.checkPermissions()
            appManager.start()
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject var appManager: AppManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: appManager.isConnected ? "circle.fill" : "circle")
                            .foregroundColor(appManager.isConnected ? .green : .gray)
                            .font(.system(size: 10))
                        
                        Text("DeskExtend")
                            .font(.system(size: 24, weight: .bold))
                    }
                    
                    Text(appManager.isConnected ? "Connected to Pi" : "Waiting for connection...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if appManager.isConnected {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.2f Mbps", appManager.bitrate))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                            
                            Text("bitrate")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                            .frame(height: 30)
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(appManager.fps) FPS")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                            
                            Text("performance")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlColor))
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .borderTop()
    }
}

struct DashboardTabView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var permissionManager: PermissionManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if !permissionManager.hasScreenRecordingPermission {
                    PermissionCard()
                        .environmentObject(permissionManager)
                } else {
                    HStack(spacing: 12) {
                        GlassCard(title: "Stream", value: appManager.isConnected ? "Active" : "Inactive") {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(appManager.piAddress, systemImage: "macbook.and.iphone")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        GlassCard(title: "Resolution", value: appManager.resolution) {
                            HStack(spacing: 4) {
                                Image(systemName: "square.fill")
                                    .font(.system(size: 8))
                                Text("1080p")
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        GlassCard(title: "Frames", value: "\(appManager.encodedFrames)") {
                            Text("sent")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        if appManager.isConnected {
                            GlassCard(title: "Uptime", value: formatUptime(appManager.uptime)) {
                                Text("connected")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct SettingsTabView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var selectedResolution = 0
    @State private var selectedFPS = 1
    @State private var bitrateValue = 8.0
    
    let resolutions = ["1920×1080", "1280×720", "1024×768"]
    let fpsModes = ["24", "30", "60"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Video Settings")
                        .font(.system(size: 16, weight: .semibold))
                    
                    GlassCard(title: "Resolution", value: resolutions[selectedResolution]) {
                        Picker("", selection: $selectedResolution) {
                            ForEach(0..<resolutions.count, id: \.self) { i in
                                Text(resolutions[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    GlassCard(title: "Frame Rate", value: "\(fpsModes[selectedFPS]) FPS") {
                        Picker("", selection: $selectedFPS) {
                            ForEach(0..<fpsModes.count, id: \.self) { i in
                                Text(fpsModes[i]).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    
                    GlassCard(title: "Bitrate", value: String(format: "%.1f Mbps", bitrateValue)) {
                        VStack(spacing: 8) {
                            Slider(value: $bitrateValue, in: 1...15, step: 0.5)
                            HStack {
                                Text("Low")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("High")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("System")
                        .font(.system(size: 16, weight: .semibold))
                    
                    GlassCard(title: "Permissions", value: permissionManager.permissionStatus) {
                        HStack(spacing: 8) {
                            if permissionManager.hasScreenRecordingPermission {
                                Label("Granted", systemImage: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.system(size: 11))
                            } else {
                                Button("Grant Access") {
                                    permissionManager.openSystemSettings()
                                }
                                .buttonStyle(.bordered)
                                .font(.system(size: 11))
                            }
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct ConnectionTabView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var piAddress = ""
    @State private var piPort = "5900"
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard(title: "Connection Status", value: appManager.isConnected ? "Connected" : "Disconnected") {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(appManager.isConnected ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(appManager.piAddress)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                }
                
                GlassCard(title: "Pi Address", value: piAddress.isEmpty ? "Auto-detect" : piAddress) {
                    VStack(spacing: 8) {
                        TextField("e.g., 192.168.1.100", text: $piAddress)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                        
                        HStack(spacing: 8) {
                            Text("Port")
                                .font(.system(size: 11))
                            Spacer()
                            TextField("5900", text: $piPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                                .font(.system(size: 11, design: .monospaced))
                        }
                    }
                }
                
                GlassCard(title: "Network", value: "Local USB") {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                        Text("Direct USB connection")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Button(action: {}) {
                        Label("Connect", systemImage: "bolt.horizontal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { appManager.stop() }) {
                        Label("Disconnect", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
                
                Spacer()
            }
            .padding()
        }
    }
}

struct PermissionCard: View {
    @EnvironmentObject var permissionManager: PermissionManager
    
    var body: some View {
        GlassCard(title: "Screen Recording", value: "Permission Required") {
            VStack(alignment: .leading, spacing: 12) {
                Text("DeskExtend needs permission to capture your screen for streaming.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Button(action: {
                    permissionManager.openSystemSettings()
                }) {
                    Label("Open System Settings", systemImage: "gear")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
}

struct GlassCard<Content: View>: View {
    let title: String
    let value: String
    let content: Content
    
    init(title: String, value: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.value = value
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    if !value.isEmpty {
                        Text(value)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                
                Spacer()
            }
            
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(nsColor: .controlColor).opacity(0.5),
                            Color(nsColor: .controlColor).opacity(0.2)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

struct MenuBarView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var permissionManager: PermissionManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle()
                    .fill(appManager.isConnected ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(appManager.isConnected ? "Connected" : "Disconnected")
                    .font(.system(size: 12, weight: .semibold))
                
                Spacer()
            }
            
            Divider()
            
            if appManager.isConnected {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Bitrate")
                            .font(.system(size: 11))
                        Spacer()
                        Text(String(format: "%.2f Mbps", appManager.bitrate))
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    HStack {
                        Text("FPS")
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(appManager.fps)")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Frames")
                            .font(.system(size: 11))
                        Spacer()
                        Text("\(appManager.encodedFrames)")
                            .font(.system(size: 11, design: .monospaced))
                    }
                    
                    HStack {
                        Text("Uptime")
                            .font(.system(size: 11))
                        Spacer()
                        Text(formatUptime(appManager.uptime))
                            .font(.system(size: 11, design: .monospaced))
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No device connected")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("Connect your Raspberry Pi to start streaming")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            
            Divider()
            
            Button(action: {
                if !appManager.windowIsOpen {
                    NSApplication.shared.setActivationPolicy(.regular)
                    DispatchQueue.main.async {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        appManager.shouldOpenWindow = true
                    }
                } else {
                    DispatchQueue.main.async {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        if let mainWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                            mainWindow.makeKeyAndOrderFront(nil)
                        }
                    }
                }
            }) {
                Label("Open DeskExtend", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                if let delegate = NSApplication.shared.delegate as? AppDelegate {
                    delegate.shouldAllowTermination = true
                }
                DispatchQueue.main.async {
                    NSApplication.shared.terminate(nil)
                    exit(0)
                }
            }) {
                Label("Quit", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 220)
    }
}

private func formatUptime(_ seconds: TimeInterval) -> String {
    let totalSeconds = Int(seconds)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    } else if minutes > 0 {
        return String(format: "%d:%02d", minutes, secs)
    } else {
        return "\(secs)s"
    }
}

extension View {
    func borderTop() -> some View {
        self.border(Color(nsColor: .separatorColor), width: 1)
    }
}
