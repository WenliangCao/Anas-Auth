import Foundation
import SwiftData
import Testing
@testable import AnasAuth

struct CodeStoreTests {
    @MainActor
    @Test func insertFetchDelete() throws {
        // ModelContext 不持有 ModelContainer，必须自己保活，否则 fetch 时容器已释放 → 崩溃
        let container = try CodeStore.makeContainer(inMemoryOnly: true)
        let context = ModelContext(container)
        let entry = CodeEntry(code: OTPCode(
            issuer: "GitHub", accountName: "alice", secret: "JBSWY3DPEHPK3PXP"
        ))
        context.insert(entry)

        var fetched = try context.fetch(FetchDescriptor<CodeEntry>())
        #expect(fetched.count == 1)
        #expect(fetched[0].issuer == "GitHub")
        #expect(fetched[0].algorithm == .sha1)
        #expect(fetched[0].type == .totp)

        context.delete(entry)
        try context.save()
        fetched = try context.fetch(FetchDescriptor<CodeEntry>())
        #expect(fetched.isEmpty)
    }

    @MainActor
    @Test func mappingRoundTripPreservesAllFields() throws {
        let original = OTPCode(
            issuer: "Steam", accountName: "gaben", secret: "ABCDEF234567",
            algorithm: .sha256, digits: 8, period: 45, counter: 7,
            type: .hotp, note: "主账号", pinned: true
        )
        let restored = CodeEntry(code: original).toOTPCode()
        #expect(restored == original)
    }
}
