import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var appManager: AppManager?
    var shouldAllowTermination = false
    var virtualDisplayManager: VirtualDisplayManager?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }
    
    @objc func windowDidBecomeKey(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    @objc func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            if window.identifier?.rawValue == "main" {
                DispatchQueue.main.async {
                    self.appManager?.windowIsOpen = false
                    NSApplication.shared.setActivationPolicy(.accessory)
                }
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if shouldAllowTermination {
            return .terminateNow
        }
        return .terminateCancel
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        virtualDisplayManager?.stop()
    }
}

@main
struct DeskExtendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appManager = AppManager()
    @StateObject private var permissionManager = PermissionManager()
    @State private var senderController: SenderController?
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        Window("DeskExtend", id: "main") {
            DashboardView()
                .environmentObject(appManager)
                .environmentObject(permissionManager)
                .frame(minWidth: 800, maxWidth: 1200, minHeight: 600, maxHeight: .infinity)
                .onAppear {
                    appDelegate.appManager = appManager
                    appManager.windowIsOpen = true
                    NSApplication.shared.setActivationPolicy(.regular)
                    
                    if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
                        window.isRestorable = false
                        window.styleMask.remove(.fullScreen)
                        window.center()
                    }
                    
                    if senderController == nil {
                        senderController = SenderController(appManager: appManager)
                        appManager.onConnectRequest = { request in
                            if appDelegate.virtualDisplayManager == nil {
                                appDelegate.virtualDisplayManager = VirtualDisplayManager()
                                appManager.virtualDisplayManager = appDelegate.virtualDisplayManager
                            }
                            appDelegate.virtualDisplayManager?.createDisplay(
                                name: ConfigurationManager.shared.virtualDisplayName,
                                width: ConfigurationManager.shared.virtualDisplaySize.width,
                                height: ConfigurationManager.shared.virtualDisplaySize.height
                            )
                            senderController?.connect(request: request)
                        }
                        appManager.onDisconnect = { [weak senderController, weak appDelegate] in
                            appDelegate?.virtualDisplayManager?.stop()
                            appDelegate?.virtualDisplayManager = nil
                            senderController?.stop()
                        }
                    }
                }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        MenuBarExtra("DeskExtend", systemImage: "display") {
            MenuBarView()
                .environmentObject(appManager)
                .environmentObject(permissionManager)
        }
        .onChange(of: appManager.shouldOpenWindow) { _, shouldOpen in
            if shouldOpen && !appManager.windowIsOpen {
                openWindow(id: "main")
            }
            appManager.shouldOpenWindow = false
        }
    }
}
