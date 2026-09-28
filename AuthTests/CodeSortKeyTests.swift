import Foundation
import SwiftData
import Testing
@testable import Auth

@MainActor
struct CodeSortKeyTests {
    private func entry(
        _ issuer: String,
        account: String = "",
        pinned: Bool = false,
        taps: Int = 0,
        lastUsed: Date = .distantPast
    ) -> CodeEntry {
        let entry = CodeEntry(issuer: issuer, accountName: account, secret: "JBSWY3DPEHPK3PXP", pinned: pinned)
        entry.tapCount = taps
        entry.lastUsedAt = lastUsed
        return entry
    }

    @Test func issuerUsesNaturalOrderAndPinnedFirst() {
        let entries = [entry("b10"), entry("a"), entry("b2"), entry("z", pinned: true)]
        let sorted = CodeSortKey.issuer.sorted(entries).map(\.issuer)
        #expect(sorted == ["z", "a", "b2", "b10"])
    }

    @Test func accountSortsByAccountName() {
        let entries = [entry("x", account: "bob"), entry("y", account: "alice")]
        #expect(CodeSortKey.account.sorted(entries).map(\.accountName) == ["alice", "bob"])
    }

    @Test func mostFrequentlyUsedSortsByTapCountDescending() {
        let entries = [entry("a", taps: 1), entry("b", taps: 5), entry("c", taps: 3)]
        #expect(CodeSortKey.mostFrequentlyUsed.sorted(entries).map(\.issuer) == ["b", "c", "a"])
    }

    @Test func recentlyUsedSortsByLastUsedDescending() {
        let now = Date()
        let entries = [
            entry("old", lastUsed: now.addingTimeInterval(-100)),
            entry("never"),
            entry("new", lastUsed: now),
        ]
        #expect(CodeSortKey.recentlyUsed.sorted(entries).map(\.issuer) == ["new", "old", "never"])
    }
}
