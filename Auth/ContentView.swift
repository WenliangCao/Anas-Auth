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
        .overlay {
            // 切后台/多任务时遮住内容，防止应用切换器快照泄露验证码
            if scenePhase != .active {
                Rectangle()
                    .fill(.regularMaterial)
                    .ignoresSafeArea()
                    .overlay {
                        Image(systemName: "lock.shield")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
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
