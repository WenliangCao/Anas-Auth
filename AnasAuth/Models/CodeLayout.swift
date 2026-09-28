import Foundation

/// 首页卡片布局（对齐 ente 的紧凑模式）
enum CodeLayout: String, CaseIterable, Identifiable {
    case standard
    case compact

    var id: Self { self }

    var title: String {
        switch self {
        case .standard: String(localized: "Default")
        case .compact: String(localized: "Compact")
        }
    }
}
