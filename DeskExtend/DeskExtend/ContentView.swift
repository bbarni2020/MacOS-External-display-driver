import SwiftUI

struct ContentView: View {
    var body: some View {
        DashboardView()
            .environmentObject(AppManager())
            .environmentObject(PermissionManager())
    }
}
