import PhinTechStoreKit
import AppKit
import CoreText
import SwiftUI

/// The words and layout of an app's magazine-ad page, from Ads.json. Apps the store has no copy for
/// get a plain ad built from the catalog's description.
struct AdCopy: Codable {
    enum Layout: String, Codable { case classic, photo, columns, product }
    struct Section: Codable, Hashable {
        var heading: String?
        var body: String
    }

    var layout: Layout
    var boxColor: String
    var headline: String
    var kicker: String?
    var sections: [Section]
    var tagline: String
    var finePrint: String?

    private static let all: [String: AdCopy] = {
        guard let url = Bundle.main.url(forResource: "Ads", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: AdCopy].self, from: data)) ?? [:]
    }()

    static func `for`(_ app: StoreApp) -> AdCopy {
        if let copy = all[app.id] { return copy }
        let palette = ["#7C2D12", "#1E3A8A", "#14532D", "#581C87", "#0F766E", "#9F1239"]
        let pick = palette[abs(app.id.hashValue) % palette.count]
        return AdCopy(layout: .classic, boxColor: pick, headline: app.title + ".",
                      kicker: nil, sections: [.init(body: app.summary)],
                      tagline: "From Phin Tech.", finePrint: nil)
    }
}

@MainActor
enum Art {
    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String) -> NSImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Art")
                ?? Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Art"),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[name] = image
        return image
    }
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
