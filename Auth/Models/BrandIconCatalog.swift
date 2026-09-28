import Foundation

/// 一个品牌图标（来自 simple-icons，矢量图在 BrandIcons.xcassets/brand 下）
struct BrandIcon: Decodable, Hashable, Identifiable, Sendable {
    let slug: String
    let title: String
    /// 品牌色，6 位十六进制，不带 #
    let hex: String

    var id: String { slug }
    var assetName: String { "brand/\(slug)" }
}

/// 品牌图标目录：按 slug 取图标，或按发行方名称自动匹配。
/// 数据由 Scripts/generate_brand_icons.mjs 生成。
enum BrandIconCatalog {
    private struct Index: Decodable, Sendable {
        let icons: [BrandIcon]
        /// 规范化名称 → slug（含正式名、slug 与别名）
        let lookup: [String: String]
    }

    private static let index: Index = {
        guard let url = Bundle.main.url(forResource: "BrandIcons", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(Index.self, from: data) else {
            return Index(icons: [], lookup: [:])
        }
        return index
    }()

    private static let bySlug: [String: BrandIcon] = Dictionary(
        index.icons.map { ($0.slug, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    static var all: [BrandIcon] { index.icons }

    static func icon(slug: String) -> BrandIcon? {
        bySlug[slug]
    }

    /// 按发行方名称匹配，如 "GitHub"、"\"Discord\""
    static func match(issuer: String) -> BrandIcon? {
        index.lookup[normalize(issuer)].flatMap { bySlug[$0] }
    }

    /// 小写且只保留字母数字，与生成脚本的规则一致
    static func normalize(_ text: String) -> String {
        String(String.UnicodeScalarView(
            text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        ))
    }
}
