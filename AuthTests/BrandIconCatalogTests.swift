import Testing
@testable import Auth

struct BrandIconCatalogTests {
    @Test func catalogLoadsFromBundle() {
        #expect(BrandIconCatalog.all.count > 1000)
    }

    @Test func matchesIssuerIgnoringCaseAndSymbols() {
        #expect(BrandIconCatalog.match(issuer: "GitHub")?.slug == "github")
        #expect(BrandIconCatalog.match(issuer: "\"discord\"")?.slug == "discord")
        #expect(BrandIconCatalog.match(issuer: " Google ")?.slug == "google")
    }

    @Test func unknownIssuerHasNoMatch() {
        #expect(BrandIconCatalog.match(issuer: "Some Internal VPN") == nil)
        #expect(BrandIconCatalog.match(issuer: "") == nil)
    }

    @Test func looksUpBySlug() {
        #expect(BrandIconCatalog.icon(slug: "github")?.title == "GitHub")
        #expect(BrandIconCatalog.icon(slug: "not-a-slug") == nil)
    }
}
