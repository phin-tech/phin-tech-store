import Foundation

/// The catalog that apps.phin.tech publishes at /apps.json.
public struct CatalogFile: Codable, Sendable {
    public var apps: [String: Entry]

    public struct Entry: Codable, Sendable {
        public var title: String
        public var description: String
        public var category: String?
        public var how: String?
        public var source: String?
        public var pinned: Bool?
        public var locked: Bool?
        public var releases: [Release]
    }

    public struct Release: Codable, Hashable, Sendable {
        public var date: String
        public var file: String
        public var sha256: String
        public var size: Int64
        public var version: String
    }
}

public struct StoreApp: Identifiable, Hashable, Sendable {
    public static let site = URL(string: "https://apps.phin.tech/")!

    public let id: String
    public let title: String
    public let summary: String
    public let category: String
    public let how: String?
    public let source: URL?
    public let pinned: Bool
    public let releases: [CatalogFile.Release]

    public var latest: CatalogFile.Release? { releases.first }
    public var isMacApp: Bool { category == StoreApp.macApps }

    public static let macApps = "Mac apps"

    public func downloadURL(for release: CatalogFile.Release) -> URL {
        StoreApp.site.appendingPathComponent(id).appendingPathComponent(release.file)
    }

    public init(id: String, entry: CatalogFile.Entry) {
        self.id = id
        title = entry.title
        summary = entry.description
        category = entry.category ?? StoreApp.macApps
        how = entry.how
        source = entry.source.flatMap(URL.init(string:))
        pinned = entry.pinned ?? false
        releases = entry.releases.sorted { $0.date == $1.date ? $0.version.compare($1.version, options: .numeric) == .orderedDescending : $0.date > $1.date }
    }
}

public struct Shelf: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let apps: [StoreApp]
}

public enum CatalogLoader {
    public static let feed = URL(string: "https://apps.phin.tech/apps.json")!

    public static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Phin Tech Store", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("apps.json")
    }

    /// The last catalog fetched, so the store opens instantly and works offline.
    public static func cached() -> [Shelf]? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        return try? shelves(from: data)
    }

    public static func fetch() async throws -> [Shelf] {
        var request = URLRequest(url: feed)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let result = try shelves(from: data)
        try? data.write(to: cacheURL, options: .atomic)
        return result
    }

    public static func shelves(from data: Data) throws -> [Shelf] {
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        let apps = file.apps.map { StoreApp(id: $0.key, entry: $0.value) }.filter { $0.latest != nil }
        let grouped = Dictionary(grouping: apps, by: \.category)
        let names = grouped.keys.sorted { a, b in
            if a == StoreApp.macApps { return true }
            if b == StoreApp.macApps { return false }
            return a < b
        }
        return names.map { name in
            Shelf(name: name, apps: grouped[name]!.sorted { a, b in
                if a.pinned != b.pinned { return a.pinned }
                return (a.latest?.date ?? "") > (b.latest?.date ?? "")
            })
        }
    }
}
