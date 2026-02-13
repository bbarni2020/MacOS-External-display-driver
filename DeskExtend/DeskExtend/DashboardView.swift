import SwiftUI
import AppKit

struct DashboardView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var permissionManager: PermissionManager
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.04, green: 0.05, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
                    
                    ConnectionTabView()
                        .environmentObject(appManager)
                        .tabItem {
                            Label("Connection", systemImage: "wifi")
                        }
                        .tag(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
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
                        Image(systemName: appManager.isConnected ? "dot.radiowaves.left.and.right" : "wifi.slash")
                            .foregroundColor(appManager.isConnected ? Color.green : Color.gray)
                            .font(.system(size: 14))
                        
                        Text("DeskExtend")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    
                    Text(appManager.isConnected ? "Connected to Pi" : "Waiting for connection...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                if appManager.isConnected {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.2f Mbps", appManager.bitrate))
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            
                                            .textSelection(.enabled)
                                            .lineLimit(nil)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Divider()
                            .frame(height: 30)
                        
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(appManager.fps) FPS")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            
                            Text("performance")
                                .font(.system(size: 10))
                                .foregroundColor(.gray)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(10)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 16)
        }
        .background(Color.white.opacity(0.02))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color.white.opacity(0.05)), alignment: .bottom)
    }
}

struct DashboardTabView: View {
    @EnvironmentObject var appManager: AppManager
    @EnvironmentObject var permissionManager: PermissionManager
    
    let resolutions = ["1920×1080", "1280×720", "1024×768"]
    let fpsModes = ["24", "30", "60"]
    
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Video Settings")
                            .font(.system(size: 16, weight: .semibold))
                        
                        let resolutionLabel = resolutions.indices.contains(appManager.selectedResolutionIndex) ? resolutions[appManager.selectedResolutionIndex] : resolutions.first ?? ""
                        GlassCard(title: "Resolution", value: resolutionLabel) {
                            Picker("", selection: $appManager.selectedResolutionIndex) {
                                ForEach(0..<resolutions.count, id: \.self) { i in
                                    Text(resolutions[i]).tag(i)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        let fpsLabel = fpsModes.indices.contains(appManager.selectedFpsIndex) ? fpsModes[appManager.selectedFpsIndex] : fpsModes.first ?? ""
                        GlassCard(title: "Frame Rate", value: "\(fpsLabel) FPS") {
                            Picker("", selection: $appManager.selectedFpsIndex) {
                                ForEach(0..<fpsModes.count, id: \.self) { i in
                                    Text(fpsModes[i]).tag(i)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                        
                        GlassCard(title: "Bitrate", value: String(format: "%.1f Mbps", appManager.bitrateMbps)) {
                            VStack(spacing: 8) {
                                Slider(value: $appManager.bitrateMbps, in: 1...15, step: 0.5)
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

                        GlassCard(title: "Virtual Display", value: "\(appManager.virtualDisplayWidth)×\(appManager.virtualDisplayHeight)") {
                            VStack(alignment: .leading, spacing: 8) {
                                TextField("Display Name", text: $appManager.virtualDisplayName)
                                    .textFieldStyle(.roundedBorder)
                                HStack {
                                    TextField("Width", value: $appManager.virtualDisplayWidth, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                    TextField("Height", value: $appManager.virtualDisplayHeight, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button("Apply") {
                                    appManager.applyVirtualDisplayConfig()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding()
        }
    }
}

struct ConnectionTabView: View {
    @EnvironmentObject var appManager: AppManager
    @State private var piAddressInput = ""
    @State private var piPort = ""
    @State private var usbDeviceInput = ""
    
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

                GlassCard(title: "Mode", value: appManager.connectionMode.label) {
                    Picker("", selection: $appManager.connectionMode) {
                        ForEach(ConnectionMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                GlassCard(title: "Pi Address", value: piAddressInput.isEmpty ? "Auto-detect" : piAddressInput) {
                    VStack(spacing: 8) {
                        TextField("e.g., 192.168.1.100", text: $piAddressInput)
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

                if appManager.connectionMode != .network {
                    GlassCard(title: "USB Device", value: usbDeviceInput.isEmpty ? appManager.usbDevice : usbDeviceInput) {
                        VStack(spacing: 8) {
                            if !appManager.usbDevices.isEmpty {
                                Picker("USB", selection: $appManager.usbDevice) {
                                    ForEach(appManager.usbDevices, id: \.self) { dev in
                                        Text(dev).tag(dev)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)
                            }
                            TextField("/dev/cu.usbmodemXXXX", text: $usbDeviceInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                            HStack(spacing: 8) {
                                Button(action: { appManager.refreshUsbDevices() }) {
                                    Label("Rescan", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                                Button(action: {
                                    appManager.usbDevice = usbDeviceInput.isEmpty ? appManager.usbDevice : usbDeviceInput
                                    usbDeviceInput = appManager.usbDevice
                                }) {
                                    Label("Use Manual", systemImage: "pencil")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }
                
                GlassCard(title: "Network", value: "TCP Stream") {
                    HStack(spacing: 8) {
                        Image(systemName: "network")
                            .foregroundColor(.blue)
                        Text("Hardware-accelerated H.264")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 12) {
                    Button(action: {
                        let trimmed = piAddressInput.trimmingCharacters(in: .whitespaces)
                        let port = Int(piPort) ?? 5900
                        appManager.usbDevice = usbDeviceInput.isEmpty ? appManager.usbDevice : usbDeviceInput
                        appManager.connect(to: trimmed, port: port)
                    }) {
                        Label("Connect", systemImage: "bolt.horizontal.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    
                    Button(action: { appManager.disconnect() }) {
                        Label("Disconnect", systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }

                GlassCard(title: "Connection Logs", value: "Live") {
                    VStack(spacing: 6) {
                        HStack {
                            Spacer()
                            Button(action: {
                                let text = appManager.logs.joined(separator: "\n")
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(text, forType: .string)
                                appManager.appendLog("Connection logs copied to clipboard")
                            }) {
                                Label("Copy Logs", systemImage: "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                        }

                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(Array(appManager.logs.suffix(50).enumerated()), id: \.offset) { idx, line in
                                        Text(line)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .id(idx)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .onReceive(appManager.$logs) { _ in
                                if !appManager.logs.isEmpty {
                                    let lastIdx = appManager.logs.count - 1
                                    withAnimation(.none) {
                                        proxy.scrollTo(lastIdx, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .frame(height: 150)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if piAddressInput.isEmpty {
                piAddressInput = appManager.networkHost
            }
            if piPort.isEmpty {
                piPort = "\(appManager.networkPort)"
            }
            if usbDeviceInput.isEmpty {
                usbDeviceInput = appManager.usbDevice
            }
            appManager.refreshUsbDevices()
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
                        .foregroundColor(.gray)
                    
                    if !value.isEmpty {
                        Text(value)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
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
                        colors: [Color.white.opacity(0.06), Color.white.opacity(0.03)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .background(Color.black.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
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
