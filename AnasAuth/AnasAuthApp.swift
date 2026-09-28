import SwiftUI
import SwiftData

@main
struct AnasAuthApp: App {
    let container: ModelContainer

    init() {
        if let persistent = try? CodeStore.makeContainer() {
            container = persistent
        } else {
            // 极端情况下（如存储损坏）退化为内存库，保证 App 可用
            container = try! CodeStore.makeContainer(inMemoryOnly: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
