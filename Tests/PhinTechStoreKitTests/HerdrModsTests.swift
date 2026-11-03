import Foundation
import Testing
@testable import PhinTechStoreKit

/// A scratch home and an unpacked release in the shape app-release's herdr-mod kind zips.
private struct Fixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("herdr-mods-\(UUID().uuidString)")
    var home: URL { root.appendingPathComponent("home") }
    var unpacked: URL { root.appendingPathComponent("unpacked") }

    init(version: String = "0.4.4", mods: [String] = ["phin-picker", "phin-worktrees"], keys: String? = #"{"global": {"cmd-o": "phin-picker", "cmd-shift-o": "phin-picker:branches"}}"#) throws {
        let fm = FileManager.default
        let top = unpacked.appendingPathComponent("herdr-phin-picker-\(version)")
        for name in mods {
            let dir = top.appendingPathComponent("mods/\(name)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try #"{ "version": "\#(version)", "title": "\#(name)" }"#.write(to: dir.appendingPathComponent("mod.json"), atomically: true, encoding: .utf8)
            try "// \(name)".write(to: dir.appendingPathComponent("main.js"), atomically: true, encoding: .utf8)
        }
        if let keys { try keys.write(to: top.appendingPathComponent("keys.json"), atomically: true, encoding: .utf8) }
        let manifest = HerdrMods.Manifest(version: version, mods: mods, keys: keys == nil ? nil : "keys.json")
        try JSONEncoder().encode(manifest).write(to: top.appendingPathComponent("herdr-mod.json"))
        try fm.createDirectory(at: home.appendingPathComponent("mods"), withIntermediateDirectories: true)
    }

    func discard(_ url: URL) throws { try FileManager.default.removeItem(at: url) }
}

@Test func nothingInstalledReadsAsNotInstalled() throws {
    let f = try Fixture()
    #expect(HerdrMods.status(of: ["phin-picker"], home: f.home) == .notInstalled)
}

@Test func installCopiesEveryModAndAddsTheFreeKeys() throws {
    let f = try Fixture()
    try #"{"global": {"cmd-o": "something-else"}, "local": {"x": 1}}"#.write(to: f.home.appendingPathComponent("keys.json"), atomically: true, encoding: .utf8)
    let result = try HerdrMods.install(fromUnpacked: f.unpacked, home: f.home, discard: f.discard)
    #expect(result.version == "0.4.4")
    #expect(result.installed.map(\.lastPathComponent) == ["phin-picker", "phin-worktrees"])
    #expect(result.keysAdded == ["cmd-shift-o"] && result.keysKept == ["cmd-o"])
    let keys = try JSONSerialization.jsonObject(with: Data(contentsOf: f.home.appendingPathComponent("keys.json"))) as! [String: Any]
    let global = keys["global"] as! [String: String]
    #expect(global["cmd-o"] == "something-else")  // the user's binding wins
    #expect(global["cmd-shift-o"] == "phin-picker:branches")
    #expect(keys["local"] != nil)  // the rest of keys.json is kept
    #expect(HerdrMods.status(of: ["phin-picker"], home: f.home) == .installed(version: "0.4.4", at: f.home.appendingPathComponent("mods/phin-picker")))
}

@Test func anUpdateReplacesTheOldCopy() throws {
    let old = try Fixture(version: "0.4.3")
    _ = try HerdrMods.install(fromUnpacked: old.unpacked, home: old.home, discard: old.discard)
    try "stale".write(to: old.home.appendingPathComponent("mods/phin-picker/stale.js"), atomically: true, encoding: .utf8)
    let new = try Fixture(version: "0.4.4")
    _ = try HerdrMods.install(fromUnpacked: new.unpacked, home: old.home, discard: old.discard)
    #expect(HerdrMods.version(of: old.home.appendingPathComponent("mods/phin-picker")) == "0.4.4")
    #expect(!FileManager.default.fileExists(atPath: old.home.appendingPathComponent("mods/phin-picker/stale.js").path))
}

@Test func aLinkedModIsReportedAndNeverReplaced() throws {
    let f = try Fixture()
    let checkout = f.root.appendingPathComponent("checkout/mods/phin-picker")
    try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: f.home.appendingPathComponent("mods/phin-picker"), withDestinationURL: checkout)
    #expect(HerdrMods.status(of: ["phin-picker"], home: f.home) == .linked(to: checkout.standardizedFileURL))
    #expect(throws: ModError.self) { try HerdrMods.install(fromUnpacked: f.unpacked, home: f.home, discard: f.discard) }
    // Nothing was changed, not even the other mod.
    #expect(!FileManager.default.fileExists(atPath: f.home.appendingPathComponent("mods/phin-worktrees").path))
}

@Test func aReleaseWithoutKeysLeavesKeysJsonAlone() throws {
    let f = try Fixture(keys: nil)
    let result = try HerdrMods.install(fromUnpacked: f.unpacked, home: f.home, discard: f.discard)
    #expect(result.keysAdded.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: f.home.appendingPathComponent("keys.json").path))
}

@Test func modNamesThatCouldEscapeTheModsFolderAreRefused() throws {
    let f = try Fixture(mods: ["../evil"])
    #expect(throws: ModError.self) { try HerdrMods.install(fromUnpacked: f.unpacked, home: f.home, discard: f.discard) }
    #expect(HerdrMods.status(of: ["../evil"], home: f.home) == .notInstalled)
}

@Test func aCatalogEntryWithModsIsAHerdrModNotAMacApp() throws {
    let entry = try JSONDecoder().decode(CatalogFile.Entry.self, from: #"""
        {"title": "Phin Picker", "description": "d", "category": "Herdr app mods", "mods": ["phin-picker", "phin-worktrees"],
         "releases": [{"date": "2026-11-03", "file": "herdr-phin-picker-0.4.4.zip", "sha256": "aa", "size": 1, "version": "0.4.4"}]}
        """#.data(using: .utf8)!)
    let app = StoreApp(id: "herdr-phin-picker", entry: entry)
    #expect(app.isHerdrMod && !app.isMacApp)
    #expect(app.mods == ["phin-picker", "phin-worktrees"])
}
