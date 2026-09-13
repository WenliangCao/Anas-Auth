import SwiftUI

struct ContentView: View {
    @State private var lockManager = AppLockManager.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if lockManager.isEnabled && lockManager.isLocked {
                LockedView { await lockManager.unlock() }
            } else {
                CodeListView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                lockManager.lock()
            }
        }
    }
}

#Preview {
    ContentView()
}
