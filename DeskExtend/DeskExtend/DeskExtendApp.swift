import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var appManager: AppManager?
    var shouldAllowTermination = false
    
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
    }
    
    @objc func windowDidBecomeKey(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }
    
    @objc func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            self.appManager?.windowIsOpen = false
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        return shouldAllowTermination ? .terminateNow : .terminateCancel
    }
}

@main
struct DeskExtendApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appManager = AppManager()
    @StateObject private var permissionManager = PermissionManager()
    @Environment(\.openWindow) private var openWindow
    
    var body: some Scene {
        Window("DeskExtend", id: "main", content: {
            DashboardView()
                .environmentObject(appManager)
                .environmentObject(permissionManager)
                .frame(minWidth: 900, minHeight: 700)
                .onAppear {
                    appDelegate.appManager = appManager
                    appManager.windowIsOpen = true
                    NSApplication.shared.setActivationPolicy(.regular)
                }
        })
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        
        MenuBarExtra("DeskExtend", systemImage: appManager.isConnected ? "display.trianglebadge.exclamationmark.fill" : "display") {
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
