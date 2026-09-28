import SwiftUI

struct LockedView: View {
    let unlock: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Locked", systemImage: "lock.fill")
        } description: {
            Text("Verify your identity to view your codes")
        } actions: {
            Button("Unlock") {
                Task { await unlock() }
            }
            .glassButtonStyle()
        }
        .task {
            await unlock()
        }
    }
}
