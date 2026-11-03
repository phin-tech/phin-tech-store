import AppKit
import CoreText
import CryptoKit
import PhinTechStoreKit
import SwiftUI

/// Ad copy and per-app art. The copy bundled in the app (content/, as it was when the app was built) is the
/// fallback; on launch and on Reload the store reads `_store/content.json` from apps.phin.tech and downloads any
/// picture it doesn't have yet, so a new app's ad needs `just publish-content`, not a new release of the store.
@MainActor
final class StoreContent: ObservableObject {
    static let shared = StoreContent()

    @Published private(set) var manifest: ContentManifest
    /// Goes up whenever a picture arrives, so views showing art redraw.
    @Published private(set) var revision = 0

    private let bundled: [String: AdCopy]
    private let bundledStore: [String: String]
    private var images: [String: NSImage] = [:]
    private var fetching = false
    private let fm = FileManager.default

    private static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Phin Tech Store/content", isDirectory: true)
    }
    private static var manifestCache: URL { dir.appendingPathComponent("content.json") }
    private static var artDir: URL { dir.appendingPathComponent("art", isDirectory: true) }

    private init() {
        let url = Bundle.main.url(forResource: "ads", withExtension: "json", subdirectory: "content")
        bundled = url.flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: AdCopy].self, from: $0) } ?? [:]
        bundledStore = Bundle.main.url(forResource: "store", withExtension: "json", subdirectory: "content")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        let cached = (try? Data(contentsOf: Self.manifestCache))
            .flatMap { try? JSONDecoder().decode(ContentManifest.self, from: $0) }
        manifest = cached ?? ContentManifest(ads: [:], art: [:])
    }

    /// The hotline, from apps.phin.tech or else as the store was built with it.
    var hotline: Hotline? {
        Hotline(number: manifest.hotline ?? bundledStore["hotline"], page: manifest.hotlineUrl ?? bundledStore["hotlineUrl"])
    }

    func ad(for app: StoreApp) -> AdCopy {
        manifest.ads[app.id] ?? bundled[app.id] ?? .plain(for: app)
    }

    /// Per-app art (`<id>-box`, `<id>-hero`): a downloaded copy, else the bundled one. Shared art (the wood, the
    /// shop, Pepper) is only in the bundle.
    func image(_ name: String) -> NSImage? {
        if let hit = images[name] { return hit }
        var candidates: [URL?] = []
        if let file = manifest.art[name] {
            candidates.append(Self.artDir.appendingPathComponent(ContentManifest.cachedName(name, file)))
        }
        candidates += [Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "content/art"),
                       Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Art"),
                       Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Art")]
        for case let url? in candidates where fm.fileExists(atPath: url.path) {
            if let image = NSImage(contentsOf: url) { images[name] = image; return image }
        }
        return nil
    }

    /// Reads the manifest and fetches the art it lists that isn't here yet. Quiet on failure: the store keeps
    /// what it has.
    func refresh() async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        var request = URLRequest(url: ContentManifest.url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let fresh = try? JSONDecoder().decode(ContentManifest.self, from: data) else { return }
        try? fm.createDirectory(at: Self.artDir, withIntermediateDirectories: true)
        try? data.write(to: Self.manifestCache, options: .atomic)
        if fresh != manifest {
            manifest = fresh
            images.removeAll()
            revision += 1
        }
        for (name, file) in fresh.art {
            let dest = Self.artDir.appendingPathComponent(ContentManifest.cachedName(name, file))
            if fm.fileExists(atPath: dest.path) { continue }
            let source = ContentManifest.base.appendingPathComponent(file.file)
            guard let (bytes, reply) = try? await URLSession.shared.data(from: source),
                  (reply as? HTTPURLResponse)?.statusCode == 200,
                  SHA256.hash(data: bytes).map({ String(format: "%02x", $0) }).joined() == file.sha256.lowercased()
            else { continue }
            try? bytes.write(to: dest, options: .atomic)
            images[name] = nil
            revision += 1
        }
        prune(keeping: fresh)
    }

    /// Removes downloaded pictures the manifest no longer lists (old versions of changed art).
    private func prune(keeping manifest: ContentManifest) {
        let wanted = Set(manifest.art.map { ContentManifest.cachedName($0.key, $0.value) })
        for file in (try? fm.contentsOfDirectory(atPath: Self.artDir.path)) ?? [] where !wanted.contains(file) {
            try? fm.removeItem(at: Self.artDir.appendingPathComponent(file))
        }
    }
}

extension AdCopy {
    @MainActor static func `for`(_ app: StoreApp) -> AdCopy { StoreContent.shared.ad(for: app) }
}

@MainActor
enum Art {
    static func image(_ name: String) -> NSImage? { StoreContent.shared.image(name) }
}

enum Typeface {
    static func registerFonts() {
        guard let dir = Bundle.main.url(forResource: "Fonts", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "otf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }

    static func garamond(_ size: CGFloat, _ weight: String = "Regular") -> Font {
        .custom("EBGaramond-" + weight, fixedSize: size)
    }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    static let paper = Color(red: 0.965, green: 0.945, blue: 0.895)
    static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
    static let brass = Color(red: 0.80, green: 0.64, blue: 0.33)
    static let rainbow: [Color] = [
        Color(hex: "#61BB46"), Color(hex: "#FDB827"), Color(hex: "#F5821F"),
        Color(hex: "#E03A3E"), Color(hex: "#963D97"), Color(hex: "#009DDC"),
    ]
}
