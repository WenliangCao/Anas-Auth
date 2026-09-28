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

    /// 新增走去重并立即保存，重复条目只计入跳过
    @MainActor
    @Test func addCodesDedupesAndSaves() throws {
        let container = try CodeStore.makeContainer(inMemoryOnly: true)
        let context = ModelContext(container)
        let github = OTPCode(issuer: "GitHub", accountName: "alice", secret: "JBSWY3DPEHPK3PXP")
        let gitlab = OTPCode(issuer: "GitLab", accountName: "alice", secret: "GEZDGNBVGY3TQOJQ")

        #expect(try context.addCodes([github]) == (added: 1, skipped: 0))
        #expect(try context.addCodes([github, gitlab, gitlab]) == (added: 1, skipped: 2))
        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<CodeEntry>()) == 2)
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
