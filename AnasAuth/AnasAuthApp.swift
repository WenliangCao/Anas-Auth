import SwiftUI
import SwiftData

@main
struct AnasAuthApp: App {
    /// 打不开持久化存储时为 nil。不退化成内存库：那样用户会以为数据丢了、重新添加，
    /// 而新加的内容重启后又会消失
    private let container = try? CodeStore.makeContainer()

    var body: some Scene {
        WindowGroup {
            if let container {
                ContentView()
                    .modelContainer(container)
            } else {
                StorageErrorView()
            }
        }
    }
}

/// 存储打不开时的提示页：不展示空列表，避免误导
private struct StorageErrorView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t Open Your Codes", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Your codes haven’t been changed. Quit and reopen the app, or restart your device, then try again.")
        }
    }
}
