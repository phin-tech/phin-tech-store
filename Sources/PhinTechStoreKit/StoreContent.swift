import Foundation

/// The words and layout of an app's magazine-ad page. Apps with no copy get a plain ad built from the catalog.
public struct AdCopy: Codable, Sendable, Equatable {
    public enum Layout: String, Codable, Sendable { case classic, photo, columns, product }
    public struct Section: Codable, Hashable, Sendable {
        public var heading: String?
        public var body: String
        public init(heading: String? = nil, body: String) { self.heading = heading; self.body = body }
    }

    /// The name to show, when it isn't the catalog's (which is how the .app is named, like PhinTechStore).
    public var title: String?
    public var layout: Layout
    public var boxColor: String
    public var headline: String
    public var kicker: String?
    public var sections: [Section]
    public var tagline: String
    public var finePrint: String?

    /// The ad for an app nobody has written one for: its title, its description, and a box colour that stays the
    /// same from launch to launch (so not `hashValue`, which Swift seeds afresh each run).
    public static func plain(for app: StoreApp) -> AdCopy {
        let palette = ["#7C2D12", "#1E3A8A", "#14532D", "#581C87", "#0F766E", "#9F1239"]
        let seed = app.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return AdCopy(title: nil, layout: .classic, boxColor: palette[seed % palette.count], headline: app.title + ".",
                      kicker: nil, sections: [.init(body: app.summary)], tagline: "From Phin Tech.", finePrint: nil)
    }
}

/// `_store/content.json` on the download page: every app's ad copy, and the art files with their checksums, so the
/// store fetches only the pictures it doesn't have. `tools/publish-content.py` writes it from content/.
public struct ContentManifest: Codable, Sendable, Equatable {
    public struct ArtFile: Codable, Sendable, Equatable {
        /// The file's path under `_store/`, like `art/Dottie-box.jpg`.
        public var file: String
        public var sha256: String
    }

    public var ads: [String: AdCopy]
    /// Keyed by the art's name, like `Dottie-box`.
    public var art: [String: ArtFile]

    public static let base = URL(string: "https://apps.phin.tech/_store/")!
    public static var url: URL { base.appendingPathComponent("content.json") }

    public init(ads: [String: AdCopy], art: [String: ArtFile]) { self.ads = ads; self.art = art }

    /// Where a downloaded copy of `name` is kept: its checksum is in the file name, so a changed picture is a new
    /// file and an unchanged one is never fetched twice.
    public static func cachedName(_ name: String, _ file: ArtFile) -> String {
        let ext = (file.file as NSString).pathExtension
        return "\(name)-\(file.sha256.prefix(16)).\(ext.isEmpty ? "jpg" : ext)"
    }
}
