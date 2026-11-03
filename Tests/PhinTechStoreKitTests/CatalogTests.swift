import Foundation
import Testing
@testable import PhinTechStoreKit

/// A cut-down apps.json in the shape apps.phin.tech publishes.
private let sample = """
{"private": true, "apps": {
  "Old": {"title": "Old", "description": "d", "releases": [
    {"date": "2026-01-01", "file": "Old-1.0.zip", "sha256": "aa", "size": 10, "version": "1.0"}]},
  "Fresh": {"title": "Fresh", "description": "d", "releases": [
    {"date": "2026-10-01", "file": "Fresh-0.9.zip", "sha256": "bb", "size": 10, "version": "0.9"},
    {"date": "2026-11-01", "file": "Fresh-0.10.zip", "sha256": "cc", "size": 10, "version": "0.10"}]},
  "plug": {"title": "Plug", "description": "d", "category": "Herdr plugins", "how": "Run `x`.",
           "source": "https://github.com/phin-tech/plug", "releases": [
    {"date": "2026-10-28", "file": "plug-1.zip", "sha256": "dd", "size": 10, "version": "1"}]},
  "Empty": {"title": "Empty", "description": "no releases", "releases": []},
  "Srv": {"title": "Srv", "description": "a server", "category": "Servers", "how": "Run `git clone x`.",
          "source": "https://git.phin.tech/sam/srv", "releases": []}
}}
""".data(using: .utf8)!

@Test func macAppsComeFirstAndOtherCategoriesFollow() throws {
    let shelves = try CatalogLoader.shelves(from: sample)
    #expect(shelves.map(\.name) == ["Mac apps", "Herdr plugins", "Servers"])
}

@Test func appsWithoutReleasesAreLeftOff() throws {
    let names = try CatalogLoader.shelves(from: sample).flatMap(\.apps).map(\.id)
    #expect(!names.contains("Empty"))
}

@Test func aSourceWithoutReleasesIsAListing() throws {
    let shelves = try CatalogLoader.shelves(from: sample)
    let srv = try #require(shelves.first { $0.name == "Servers" }?.apps.first)
    #expect(srv.id == "Srv")
    #expect(srv.isListing && srv.latest == nil)
    #expect(srv.platform == "Server Edition")
    #expect(!shelves[0].apps[0].isListing)
    #expect(shelves[0].apps[0].platform == "for macOS")
    #expect(shelves[1].apps[0].platform == "for Herdr")
}

@Test func newestReleaseFirstAndNewestAppsFirst() throws {
    let mac = try CatalogLoader.shelves(from: sample)[0]
    #expect(mac.apps.map(\.id) == ["Fresh", "Old"])
    #expect(mac.apps[0].latest?.version == "0.10")
}

@Test func downloadURLIsUnderTheAppsFolder() throws {
    let plug = try CatalogLoader.shelves(from: sample)[1].apps[0]
    #expect(plug.downloadURL(for: plug.latest!).absoluteString == "https://apps.phin.tech/plug/plug-1.zip")
    #expect(!plug.isMacApp)
    #expect(plug.source?.host() == "github.com")
}
