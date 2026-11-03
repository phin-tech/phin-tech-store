import Foundation
import Testing
@testable import PhinTechStoreKit

/// The shape tools/publish-content.py writes.
private let manifestJSON = """
{"ads": {"Dottie": {"layout": "photo", "boxColor": "#1F6F78", "headline": "H", "sections": [{"body": "b"}],
                    "tagline": "T"}},
 "art": {"Dottie-box": {"file": "art/Dottie-box.jpg", "sha256": "0123456789abcdef0123456789abcdef"}}}
""".data(using: .utf8)!

private func app(_ id: String) throws -> StoreApp {
    let entry = try JSONDecoder().decode(CatalogFile.Entry.self, from: """
        {"title": "\(id)", "description": "About \(id)", "releases": []}
        """.data(using: .utf8)!)
    return StoreApp(id: id, entry: entry)
}

@Test func decodesThePublishedManifest() throws {
    let m = try JSONDecoder().decode(ContentManifest.self, from: manifestJSON)
    #expect(m.ads["Dottie"]?.layout == .photo)
    #expect(m.ads["Dottie"]?.kicker == nil)
    #expect(m.art["Dottie-box"]?.file == "art/Dottie-box.jpg")
}

@Test func cachedNameChangesWithTheChecksum() throws {
    let m = try JSONDecoder().decode(ContentManifest.self, from: manifestJSON)
    var file = m.art["Dottie-box"]!
    let before = ContentManifest.cachedName("Dottie-box", file)
    #expect(before == "Dottie-box-0123456789abcdef.jpg")
    file.sha256 = "ffff" + file.sha256.dropFirst(4)
    #expect(ContentManifest.cachedName("Dottie-box", file) != before)
}

@Test func plainAdIsStableAndUsesTheCatalog() throws {
    let a = try app("Newcomer")
    let ad = AdCopy.plain(for: a)
    #expect(ad == AdCopy.plain(for: a))
    #expect(ad.headline == "Newcomer.")
    #expect(ad.sections.first?.body == "About Newcomer")
}

@Test func hotlineDialsTheDigitsAndKeepsOnlyAnHttpsPage() throws {
    let line = try #require(Hotline(number: "+1 (833) 401-2219", page: "https://hotline.phin.tech/"))
    #expect(line.dial.absoluteString == "tel:+18334012219")
    #expect(line.pageName == "hotline.phin.tech")
    #expect(Hotline(number: "+1 (833) 401-2219", page: "javascript:alert(1)")?.page == nil)
    #expect(Hotline(number: "call me", page: nil) == nil)
    #expect(Hotline(number: nil, page: nil) == nil)
}

@Test func anOlderManifestWithoutAHotlineStillDecodes() throws {
    let m = try JSONDecoder().decode(ContentManifest.self, from: #"{"ads": {}, "art": {}}"#.data(using: .utf8)!)
    #expect(m.hotline == nil && m.hotlineUrl == nil)
}
