import Foundation

/// 一个品牌图标：ente 社区图标（custom/）或 simple-icons（brand/）
struct BrandIcon: Decodable, Hashable, Identifiable, Sendable {
    /// 存进 CodeEntry.iconID 的值：simple-icons 用 slug，ente 图标用 "ente_" 前缀
    let id: String
    let title: String
    /// 品牌色，6 位十六进制，不带 #；彩色图标为 nil
    let hex: String?
    /// true 为单色模板图，按 hex 着色；false 为原色彩色图
    let tinted: Bool
    /// 资源目录里的图片名
    let asset: String
}

/// 品牌图标目录，与 ente Auth 同一套图标和匹配规则：同名时 ente 社区图标优先。
/// 数据由 Scripts/generate_brand_icons.mjs 生成。
enum BrandIconCatalog {
    private struct Index: Decodable, Sendable {
        let icons: [BrandIcon]
        /// 规范化名称 → 图标 id（含正式名、文件名与别名）
        let lookup: [String: String]
        /// 被 ente 图标取代的 simple-icons slug → 新 id，兼容旧数据
        let replaced: [String: String]
    }

    private static let index: Index = {
        guard let url = Bundle.main.url(forResource: "BrandIcons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data) else {
            return Index(icons: [], lookup: [:], replaced: [:])
        }
        return index
    }()

    private static let byID: [String: BrandIcon] = Dictionary(
        index.icons.map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    /// 按标题排序的全部图标（选择页用）
    static var all: [BrandIcon] { index.icons }

    static func icon(id: String) -> BrandIcon? {
        byID[id] ?? index.replaced[id].flatMap { byID[$0] }
    }

    /// 按发行方匹配；与 ente 一样，整体匹配不到时再试 "(" 或 "." 之前的部分，
    /// 如 "Google (Work)"、"github.com"
    static func match(issuer: String) -> BrandIcon? {
        var candidates = [issuer]
        for separator in ["(", "."] where issuer.contains(separator) {
            candidates.append(String(issuer.prefix { String($0) != separator }))
        }
        for candidate in candidates {
            if let id = index.lookup[normalize(candidate)], let icon = byID[id] {
                return icon
            }
        }
        return nil
    }

    /// 小写且只保留字母数字，与生成脚本的规则一致
    static func normalize(_ text: String) -> String {
        String(String.UnicodeScalarView(
            text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        ))
    }
}
