import PhinTechStoreKit
import SwiftUI

/// An app's page: a magazine advertisement lying on a walnut desk, with an order form to clip.
struct AdPageView: View {
    let app: StoreApp
    @ObservedObject var installer: Installer
    @ObservedObject private var content = StoreContent.shared

    private var copy: AdCopy { AdCopy.for(app) }
    private let pageWidth: CGFloat = 820

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                page
                    .frame(width: pageWidth)
                    .background(Paper())
                    .rotationEffect(.degrees(-0.4))
                    .shadow(color: .black.opacity(0.55), radius: 18, x: 4, y: 14)
                    .padding(.vertical, 48)
            }
            .frame(maxWidth: .infinity)
        }
        .background { Desk() }
    }

    @ViewBuilder private var page: some View {
        VStack(spacing: 0) {
            switch copy.layout {
            case .classic: ClassicAd(app: app, copy: copy)
            case .photo: PhotoAd(app: app, copy: copy)
            case .columns: ColumnsAd(app: app, copy: copy)
            case .product: ProductAd(app: app, copy: copy)
            }
            OrderForm(app: app, installer: installer)
                .padding(.horizontal, 56)
                .padding(.top, 28)
            FinePrint(app: app, text: copy.finePrint)
                .padding(.horizontal, 56)
                .padding(.vertical, 22)
        }
    }
}

// MARK: - Surfaces

struct Desk: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.28, green: 0.15, blue: 0.07)
                if let wood = Art.image("wood-shelf") {
                    Image(nsImage: wood).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
                RadialGradient(colors: [Color(hex: "#FFD89A").opacity(0.18), .black.opacity(0.6)], center: .init(x: 0.5, y: 0.2),
                               startRadius: 50, endRadius: max(geo.size.width, geo.size.height) * 0.8)
            }
        }
        .ignoresSafeArea()
    }
}

/// Coated magazine stock, a little yellowed at the edges.
struct Paper: View {
    var body: some View {
        ZStack {
            Color.paper
            RadialGradient(colors: [.clear, Color(hex: "#C8B48A").opacity(0.28)], center: .center, startRadius: 200, endRadius: 700)
            Canvas { ctx, size in
                var rng = SystemRandomNumberGeneratorish(seed: 7)
                for _ in 0..<Int(size.width * size.height / 260) {
                    let x = rng.next() * size.width, y = rng.next() * size.height
                    ctx.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(.black.opacity(0.05 * rng.next())))
                }
            }
        }
    }
}

/// A tiny deterministic generator, so the paper grain doesn't shimmer as the page redraws.
struct SystemRandomNumberGeneratorish {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state ^= state << 13; state ^= state >> 7; state ^= state << 17
        return CGFloat(state % 10_000) / 10_000
    }
}

// MARK: - Type helpers

private struct Headline: View {
    let text: String
    var size: CGFloat = 64
    var alignment: TextAlignment = .center
    var color: Color = .ink

    var body: some View {
        Text(text)
            .font(Typeface.garamond(size, "Bold"))
            .tracking(-size * 0.028)
            .lineSpacing(-size * 0.12)
            .multilineTextAlignment(alignment)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct BodyCopy: View {
    let sections: [AdCopy.Section]
    var size: CGFloat = 16.5
    var indent = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sections, id: \.self) { s in
                if let heading = s.heading {
                    Text(heading)
                        .font(Typeface.garamond(size + 6, "Bold"))
                        .tracking(-0.3)
                        .padding(.top, 6)
                }
                Text((indent && s.heading == nil ? "\u{2003}" : "") + s.body)
                    .font(Typeface.garamond(size))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(Color.ink)
    }
}

private struct Hero: View {
    let app: StoreApp
    @ObservedObject private var content = StoreContent.shared
    var aspect: CGFloat = 4 / 3

    var body: some View {
        Color.black
            .aspectRatio(aspect, contentMode: .fit)
            .overlay {
                if let image = Art.image("\(app.id)-hero") {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: AdCopy.for(app).boxColor), .black], startPoint: .top, endPoint: .bottom)
                }
            }
            .clipped()
    }
}

private struct Signoff: View {
    let tagline: String
    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            Text(tagline)
                .font(Typeface.garamond(28, "Medium"))
                .tracking(-0.4)
            Spacer()
            Wordmark(size: 46)
        }
        .foregroundStyle(Color.ink)
    }
}

// MARK: - Layouts

/// A big centred headline over a picture on the left and a ragged column on the right.
private struct ClassicAd: View {
    let app: StoreApp
    let copy: AdCopy

    var body: some View {
        VStack(spacing: 30) {
            Headline(text: copy.headline, size: 70)
                .frame(maxWidth: 640)
                .padding(.top, 56)
            HStack(alignment: .top, spacing: 26) {
                Hero(app: app)
                    .frame(width: 330)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                BodyCopy(sections: copy.sections)
            }
            Signoff(tagline: copy.tagline)
        }
        .padding(.horizontal, 56)
    }
}

/// A full-bleed photograph with the headline reversed out of the top, copy in two columns below.
private struct PhotoAd: View {
    let app: StoreApp
    let copy: AdCopy

    var body: some View {
        VStack(spacing: 26) {
            Hero(app: app, aspect: 4 / 3)
                .overlay(alignment: .top) {
                    VStack(spacing: 8) {
                        if let kicker = copy.kicker, !kicker.isEmpty {
                            Text(kicker)
                                .font(Typeface.garamond(40, "Bold"))
                                .tracking(-1)
                        }
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 6)
                    .padding(.top, 34)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom).frame(height: 170), alignment: .top)
                }
            VStack(spacing: 22) {
                Headline(text: copy.headline, size: 44)
                TwoColumns(sections: copy.sections)
                Signoff(tagline: copy.tagline)
            }
            .padding(.horizontal, 56)
        }
    }
}

/// A huge headline, two columns of copy with run-in heads, and a picture along the bottom.
private struct ColumnsAd: View {
    let app: StoreApp
    let copy: AdCopy

    var body: some View {
        VStack(spacing: 26) {
            Headline(text: copy.headline, size: 54)
                .padding(.top, 50)
            TwoColumns(sections: copy.sections)
            HStack(alignment: .bottom, spacing: 24) {
                Hero(app: app, aspect: 16 / 10)
                    .frame(width: 430)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
                VStack(alignment: .trailing, spacing: 10) {
                    Text(copy.tagline)
                        .font(Typeface.garamond(22, "SemiBold"))
                        .multilineTextAlignment(.trailing)
                    Wordmark(size: 40)
                    Text("THE PHIN TECH SOFTWARE STORE")
                        .font(.custom("Futura-Bold", fixedSize: 9)).tracking(1.5)
                    Text("CIRCLE \(app.id.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % 90 } + 10)")
                        .font(.custom("Futura-Medium", fixedSize: 9)).tracking(1.5)
                }
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 56)
    }
}

/// The product, big, with a narrow column beside it and a strapline across the foot.
private struct ProductAd: View {
    let app: StoreApp
    let copy: AdCopy

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Headline(text: copy.headline, size: 56, alignment: .leading)
                .padding(.top, 50)
            HStack(alignment: .top, spacing: 26) {
                Hero(app: app, aspect: 3 / 4)
                    .frame(width: 430)
                BodyCopy(sections: copy.sections, size: 14.5, indent: false)
            }
            HStack(alignment: .lastTextBaseline) {
                PepperMark(size: 60)
                Spacer()
                Text(copy.tagline)
                    .font(Typeface.garamond(44, "Medium"))
                    .tracking(-1)
            }
            .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 56)
    }
}

private struct TwoColumns: View {
    let sections: [AdCopy.Section]

    var body: some View {
        let split = splitPoint
        HStack(alignment: .top, spacing: 30) {
            BodyCopy(sections: Array(sections[..<split]))
                .frame(maxWidth: .infinity, alignment: .topLeading)
            BodyCopy(sections: Array(sections[split...]))
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// Where to break so the columns come out about even.
    private var splitPoint: Int {
        let weights = sections.map { $0.body.count + ($0.heading == nil ? 0 : 60) }
        let half = weights.reduce(0, +) / 2
        var running = 0
        for (i, w) in weights.enumerated() {
            running += w
            if running >= half { return min(max(1, i + 1), max(1, sections.count - 1)) }
        }
        return max(1, sections.count / 2)
    }
}

private struct FinePrint: View {
    let app: StoreApp
    let text: String?
    @ObservedObject private var content = StoreContent.shared

    /// The ad's own fine print, then the call-your-dealer line, with the hotline as links.
    private var words: AttributedString {
        var dealer = "For the nearest authorized Phin Tech dealer, visit [apps.phin.tech](https://apps.phin.tech)."
        if let line = content.hotline {
            dealer = "For the nearest authorized Phin Tech dealer, call the hotline: [\(line.number)](\(line.dial.absoluteString))"
                + (line.page.map { " or visit [\(line.pageName ?? $0.absoluteString)](\($0.absoluteString))" } ?? "") + "."
        }
        let year = Calendar.current.component(.year, from: Date())
        let plain = [text.map { $0.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")") },
                     dealer, "© \(year) Phin Tech."].compactMap { $0 }.joined(separator: " ")
        return (try? AttributedString(markdown: plain)) ?? AttributedString(plain)
    }

    var body: some View {
        Text(words)
            .tint(Color.ink)
            .font(Typeface.garamond(10.5))
            .foregroundStyle(Color.ink.opacity(0.75))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
