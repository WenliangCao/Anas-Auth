import Foundation

/// 首页排序方式（对齐 ente 的 CodeSortKey，暂不含手动排序）
enum CodeSortKey: String, CaseIterable, Identifiable {
    case issuer
    case account
    case mostFrequentlyUsed
    case recentlyUsed

    var id: Self { self }

    var title: String {
        switch self {
        case .issuer: String(localized: "Issuer")
        case .account: String(localized: "Account")
        case .mostFrequentlyUsed: String(localized: "Most Used")
        case .recentlyUsed: String(localized: "Recently Used")
        }
    }

    /// 按当前方式排序，置顶的始终排在最前（同 ente）
    func sorted(_ entries: [CodeEntry]) -> [CodeEntry] {
        entries.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            switch self {
            case .issuer:
                return lhs.issuer.localizedStandardCompare(rhs.issuer) == .orderedAscending
            case .account:
                return lhs.accountName.localizedStandardCompare(rhs.accountName) == .orderedAscending
            case .mostFrequentlyUsed:
                return lhs.tapCount > rhs.tapCount
            case .recentlyUsed:
                return lhs.lastUsedAt > rhs.lastUsedAt
            }
        }
    }
}
