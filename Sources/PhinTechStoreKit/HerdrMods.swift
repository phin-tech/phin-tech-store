import Foundation

/// Mods for the Herdr desktop app: folders of JavaScript in `~/.config/herdr-app/mods/<name>`, each with a `mod.json`
/// carrying its version. A release of one (app-release's `kind = "herdr-mod"`) is a zip with one top folder holding
/// `herdr-mod.json` ({"version", "mods", "keys"}), `mods/<name>/…` for each mod, and optionally `keys.json`.
///
/// Installing follows the mod's own install.sh: an older copy of each mod goes to the Trash, the new one is copied
/// in, and the release's key bindings are added to the app's keys.json only where the key is free. A mod that is a
/// symbolic link is someone's working checkout, and is never replaced.
public enum HerdrMods {
    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed(version: String, at: URL)
        /// The first mod is a symbolic link to a checkout (where it points).
        case linked(to: URL)
    }

    public struct Manifest: Codable, Equatable, Sendable {
        public var version: String
        public var mods: [String]
        public var keys: String?
    }

    public struct Result: Equatable, Sendable {
        public var version: String
        public var installed: [URL]
        /// Keys the release binds that were already taken in keys.json, so were left alone.
        public var keysKept: [String]
        public var keysAdded: [String]
    }

    /// `$HERDR_APP_HOME`, or `~/.config/herdr-app`, as Herdr and install.sh use.
    public static var home: URL {
        if let custom = ProcessInfo.processInfo.environment["HERDR_APP_HOME"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/herdr-app", isDirectory: true)
    }

    /// Whether the Herdr app is set up here at all (its folder exists).
    public static func hasHerdr(home: URL = home) -> Bool {
        FileManager.default.fileExists(atPath: home.path)
    }

    /// The status of a release's mods, judged by the first one (whose version is the release's).
    public static func status(of mods: [String], home: URL = home) -> Status {
        guard let first = mods.first, isPlainName(first) else { return .notInstalled }
        let dir = home.appendingPathComponent("mods").appendingPathComponent(first)
        let fm = FileManager.default
        if let target = try? fm.destinationOfSymbolicLink(atPath: dir.path) {
            return .linked(to: URL(fileURLWithPath: target, relativeTo: dir.deletingLastPathComponent()).standardizedFileURL)
        }
        guard fm.fileExists(atPath: dir.path) else { return .notInstalled }
        return .installed(version: version(of: dir) ?? "?", at: dir)
    }

    /// The `version` in a mod's mod.json.
    public static func version(of modDir: URL) -> String? {
        guard let data = try? Data(contentsOf: modDir.appendingPathComponent("mod.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    /// Installs from an unpacked release (the folder ditto made of the zip). `discard` takes an old copy away
    /// (the Trash, by default).
    public static func install(fromUnpacked folder: URL, home: URL = home,
                               discard: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) throws -> Result {
        let fm = FileManager.default
        guard let root = findRoot(in: folder) else { throw ModError("There's no herdr-mod.json in the download.") }
        let manifest: Manifest
        do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: root.appendingPathComponent("herdr-mod.json"))) }
        catch { throw ModError("The download's herdr-mod.json can't be read.") }
        guard !manifest.mods.isEmpty, manifest.mods.allSatisfy(isPlainName) else {
            throw ModError("The download names its mods in a way the store won't install.")
        }
        let modsDir = home.appendingPathComponent("mods", isDirectory: true)
        // Check everything before changing anything.
        for name in manifest.mods {
            guard fm.fileExists(atPath: root.appendingPathComponent("mods/\(name)/mod.json").path) else {
                throw ModError("The download is missing the \(name) mod.")
            }
            if (try? fm.destinationOfSymbolicLink(atPath: modsDir.appendingPathComponent(name).path)) != nil {
                throw ModError("\(name) is linked to a checkout of yours. Update it there; the store leaves it alone.")
            }
        }
        try fm.createDirectory(at: modsDir, withIntermediateDirectories: true)
        var installed: [URL] = []
        for name in manifest.mods {
            let dest = modsDir.appendingPathComponent(name)
            if fm.fileExists(atPath: dest.path) { try discard(dest) }
            try fm.copyItem(at: root.appendingPathComponent("mods/\(name)"), to: dest)
            installed.append(dest)
        }
        var added: [String] = [], kept: [String] = []
        if let keysName = manifest.keys, isPlainName(keysName),
           let new = try? Data(contentsOf: root.appendingPathComponent(keysName)) {
            let file = home.appendingPathComponent("keys.json")
            let merged = try mergeKeys(existing: try? Data(contentsOf: file), adding: new)
            added = merged.added
            kept = merged.kept
            if !added.isEmpty {
                // Written beside the file and moved over it, so a failure can't damage keys.json.
                let temp = home.appendingPathComponent("keys.json.store-\(UUID().uuidString)")
                try merged.data.write(to: temp)
                _ = try fm.replaceItemAt(file, withItemAt: temp)
            }
        }
        return Result(version: manifest.version, installed: installed, keysKept: kept, keysAdded: added)
    }

    /// Adds the release's `global` key bindings to keys.json's, keeping any key already bound.
    public static func mergeKeys(existing: Data?, adding new: Data) throws -> (data: Data, added: [String], kept: [String]) {
        var current: [String: Any] = [:]
        if let existing, !existing.isEmpty {
            guard let parsed = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw ModError("keys.json isn't a JSON object, so the keys weren't added.")
            }
            current = parsed
        }
        guard let incoming = (try JSONSerialization.jsonObject(with: new) as? [String: Any])?["global"] as? [String: Any] else {
            return (existing ?? Data("{}".utf8), [], [])
        }
        var global = current["global"] as? [String: Any] ?? [:]
        var added: [String] = [], kept: [String] = []
        for key in incoming.keys.sorted() {
            if global[key] == nil { global[key] = incoming[key]; added.append(key) } else { kept.append(key) }
        }
        current["global"] = global
        let data = try JSONSerialization.data(withJSONObject: current, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        return (data, added, kept)
    }

    private static func findRoot(in folder: URL) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: folder.appendingPathComponent("herdr-mod.json").path) { return folder }
        let items = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return items.first { $0.lastPathComponent != "__MACOSX" && fm.fileExists(atPath: $0.appendingPathComponent("herdr-mod.json").path) }
    }

    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.hasPrefix(".")
    }
}

public struct ModError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}
