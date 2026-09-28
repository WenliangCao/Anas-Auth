import Testing
@testable import AnasAuth

struct BrandIconCatalogTests {
    @Test func catalogLoadsBothSources() {
        #expect(BrandIconCatalog.all.count > 3000)
        #expect(BrandIconCatalog.all.contains { $0.asset.hasPrefix("custom/") })
        #expect(BrandIconCatalog.all.contains { $0.asset.hasPrefix("brand/") })
    }

    @Test func enteCustomIconsTakePrecedence() throws {
        // simple-icons 没有 Amazon / xAI，ente 社区图标有；GitHub 两边都有，用 ente 的
        #expect(BrandIconCatalog.match(issuer: "Amazon")?.asset.hasPrefix("custom/") == true)
        #expect(BrandIconCatalog.match(issuer: "\"xAI\"")?.asset.hasPrefix("custom/") == true)
        #expect(BrandIconCatalog.match(issuer: "GitHub")?.asset.hasPrefix("custom/") == true)
    }

    @Test func matchesSimpleIconsIgnoringCaseAndSymbols() {
        #expect(BrandIconCatalog.match(issuer: "\"discord\"")?.id == "discord")
        #expect(BrandIconCatalog.match(issuer: " Spotify ")?.id == "spotify")
    }

    @Test func matchesPrefixBeforeParenthesisOrDot() {
        #expect(BrandIconCatalog.match(issuer: "Discord (work)")?.id == "discord")
        #expect(BrandIconCatalog.match(issuer: "discord.com")?.id == "discord")
    }

    @Test func unknownIssuerHasNoMatch() {
        #expect(BrandIconCatalog.match(issuer: "Some Internal VPN") == nil)
        #expect(BrandIconCatalog.match(issuer: "") == nil)
    }

    @Test func replacedSimpleIconIDsStillResolve() throws {
        // 旧版本存的 simple-icons slug "github" 现在指向 ente 的 GitHub 图标
        let icon = try #require(BrandIconCatalog.icon(id: "github"))
        #expect(icon.title == "GitHub" && icon.asset.hasPrefix("custom/"))
        #expect(BrandIconCatalog.icon(id: "not-a-slug") == nil)
    }
}
