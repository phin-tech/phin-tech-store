import PhinTechStoreKit
import AppKit
import CryptoKit
import Foundation

enum InstallState: Equatable {
    case notInstalled
    case installed(version: String, at: URL)
    case downloading(Double)
    case verifying
    case installing
    case downloaded(URL)
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .downloading, .verifying, .installing: true
        default: false
        }
    }
}

/// Downloads a release zip, checks its SHA-256 against the catalog, and for Mac apps unzips it and
/// moves the app into Applications (replacing, via the Trash, any copy already there).
@MainActor
final class Installer: ObservableObject {
    @Published private(set) var states: [String: InstallState] = [:]

    private let fm = FileManager.default
    private var installedPaths: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "installedPaths") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "installedPaths") }
    }

    func state(for app: StoreApp) -> InstallState {
        states[app.id] ?? .notInstalled
    }

    func refresh(_ apps: [StoreApp]) {
        for app in apps where !(states[app.id]?.isBusy ?? false) {
            states[app.id] = detect(app)
        }
    }

    func hasUpdate(_ app: StoreApp) -> Bool {
        guard case let .installed(version, _) = state(for: app), let latest = app.latest else { return false }
        return latest.version.compare(version, options: .numeric) == .orderedDescending
    }

    private func detect(_ app: StoreApp) -> InstallState {
        guard app.isMacApp else { return .notInstalled }
        var candidates: [URL] = []
        if let saved = installedPaths[app.id] { candidates.append(URL(fileURLWithPath: saved)) }
        let names = Set([app.title, app.id, app.title.replacingOccurrences(of: " ", with: ""),
                         app.id.replacingOccurrences(of: "-", with: " ").capitalized])
        for dir in [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            for name in names { candidates.append(dir.appendingPathComponent(name + ".app")) }
        }
        for url in candidates where fm.fileExists(atPath: url.path) {
            let version = Installer.version(of: url) ?? "?"
            return .installed(version: version, at: url)
        }
        return .notInstalled
    }

    func open(_ app: StoreApp) {
        if case let .installed(_, url) = state(for: app) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func install(_ app: StoreApp, release: CatalogFile.Release? = nil) {
        guard let release = release ?? app.latest, !state(for: app).isBusy else { return }
        states[app.id] = .downloading(0)
        Task {
            do {
                let zip = try await download(app.downloadURL(for: release), expected: release.size) { [weak self] p in
                    self?.states[app.id] = .downloading(p)
                }
                states[app.id] = .verifying
                let digest = try await Task.detached { try Installer.sha256(of: zip) }.value
                guard digest.lowercased() == release.sha256.lowercased() else {
                    try? fm.removeItem(at: zip)
                    throw StoreError("The download did not match its published checksum, so it was thrown away.")
                }
                if app.isMacApp {
                    states[app.id] = .installing
                    let installed = try await Task.detached { try Installer.installApp(fromZip: zip) }.value
                    var paths = installedPaths
                    paths[app.id] = installed.path
                    installedPaths = paths
                    let version = Installer.version(of: installed) ?? release.version
                    states[app.id] = .installed(version: version, at: installed)
                } else {
                    let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
                    let dest = downloads.appendingPathComponent(release.file)
                    try? fm.removeItem(at: dest)
                    try fm.moveItem(at: zip, to: dest)
                    states[app.id] = .downloaded(dest)
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            } catch {
                states[app.id] = .failed((error as? StoreError)?.message ?? error.localizedDescription)
            }
        }
    }

    // MARK: - Steps

    private func download(_ url: URL, expected: Int64, progress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let fm = fm
        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let task = URLSession.shared.downloadTask(with: url) { location, response, error in
                if let error { return cont.resume(throwing: error) }
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    return cont.resume(throwing: StoreError("The server answered \(http.statusCode) for \(url.lastPathComponent)."))
                }
                guard let location else { return cont.resume(throwing: URLError(.cannotOpenFile)) }
                // The system deletes `location` when this handler returns, so move it first.
                let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                do { try fm.moveItem(at: location, to: tmp); cont.resume(returning: tmp) } catch { cont.resume(throwing: error) }
            }
            observation = task.progress.observe(\.fractionCompleted) { p, _ in
                let value = p.fractionCompleted
                Task { @MainActor in progress(value) }
            }
            task.resume()
        }
    }

    /// The app's version, read from its Info.plist each time. Not `Bundle(url:)`: it caches a bundle per path, so
    /// once an app is replaced it would keep answering with the old version.
    nonisolated static func version(of app: URL) -> String? {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func installApp(fromZip zip: URL) throws -> URL {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("phin-store-" + UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work); try? fm.removeItem(at: zip) }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw StoreError("The zip would not unpack.") }

        guard let app = try findApp(in: work) else { throw StoreError("There was no app inside the zip.") }

        var lastError: Error?
        for dir in [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            let dest = dir.appendingPathComponent(app.lastPathComponent)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
                try fm.moveItem(at: app, to: dest)
                return dest
            } catch {
                lastError = error
            }
        }
        throw lastError ?? StoreError("Could not move the app into Applications.")
    }

    nonisolated private static func findApp(in dir: URL) throws -> URL? {
        let fm = FileManager.default
        let items = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        if let app = items.first(where: { $0.pathExtension == "app" }) { return app }
        for item in items where item.lastPathComponent != "__MACOSX" && (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            if let app = try findApp(in: item) { return app }
        }
        return nil
    }
}

struct StoreError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
