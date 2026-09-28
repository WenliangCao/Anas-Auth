import SwiftUI

struct LockedView: View {
    let unlock: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("已锁定", systemImage: "lock.fill")
        } description: {
            Text("验证身份后查看你的验证码")
        } actions: {
            Button("解锁") {
                Task { await unlock() }
            }
            .buttonStyle(.glass)
        }
        .task {
            await unlock()
        }
    }
}
