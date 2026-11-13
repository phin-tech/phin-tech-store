import PhinTechStoreKit
import SwiftUI

/// A boxed-software package standing on a shelf: a front face with the cover art and a spine
/// turned away from the viewer.
struct SoftwareBox: View {
    let app: StoreApp
    let state: InstallState
    let hasUpdate: Bool
    var width: CGFloat = 168

    @State private var hovering = false
    @ObservedObject private var content = StoreContent.shared

    private var copy: AdCopy { AdCopy.for(app) }
    private var color: Color { Color(hex: copy.boxColor) }
    private var height: CGFloat { width * 4 / 3 }
    private var spine: CGFloat { width * 0.2 }

    var body: some View {
        HStack(spacing: 0) {
            spineFace
                .frame(width: spine, height: height)
                .modifier(SpineProjection(visibleWidth: spine * 0.5, taper: height * 0.035))
                .frame(width: spine * 0.5, alignment: .leading)
            front
                .frame(width: width, height: height)
        }
        .overlay(alignment: .topTrailing) { sticker.offset(x: 16, y: height * 0.17) }
        .compositingGroup()
        .shadow(color: .black.opacity(hovering ? 0.55 : 0.45), radius: hovering ? 14 : 5, x: 6, y: hovering ? 14 : 4)
        .offset(y: hovering ? -8 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: hovering)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(copy.title ?? app.title). \(app.summary)")
        .accessibilityAddTraits(.isButton)
    }

    private var front: some View {
        VStack(spacing: 0) {
            // Title band.
            Text((copy.title ?? app.title).uppercased())
                .font(.custom("Futura-CondensedExtraBold", fixedSize: width * 0.105))
                .tracking(0.4)
                .lineSpacing(-2)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.paper)
                .shadow(color: .black.opacity(0.35), radius: 0, x: 1, y: 1)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity)
                .frame(height: height * 0.19)
                .background(color)
            stripes(vertical: false).frame(height: 7)
            // Cover art. Color.clear takes the space; the art fills it without driving the layout.
            Color.clear
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .overlay {
                    if let art = Art.image("\(app.id)-box") {
                        Image(nsImage: art).resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [color, .black], startPoint: .top, endPoint: .bottom)
                            .overlay(PepperMark(size: width * 0.4).opacity(0.85))
                    }
                }
                .clipped()
            // Footer.
            HStack {
                BoxBadge()
                Spacer()
                Text(app.platform)
                    .font(Typeface.garamond(10, "Italic"))
                    .foregroundStyle(Color.paper.opacity(0.9))
            }
            .padding(.horizontal, 7)
            .frame(height: height * 0.09)
            .background(Color.black.opacity(0.88))
        }
        .overlay {
            // Shrink-wrap gloss and a lit top edge.
            LinearGradient(stops: [.init(color: .white.opacity(0.28), location: 0),
                                   .init(color: .white.opacity(0.04), location: 0.35),
                                   .init(color: .clear, location: 0.6),
                                   .init(color: .black.opacity(0.12), location: 1)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .allowsHitTesting(false)
        }
        .overlay(Rectangle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
    }

    private var spineFace: some View {
        ZStack {
            color.brightness(-0.18)
            HStack(spacing: 0) {
                stripes(vertical: true).frame(width: 4)
                Spacer()
            }
            Text((copy.title ?? app.title).uppercased())
                .font(.custom("Futura-Bold", fixedSize: 11))
                .tracking(2)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Color.paper)
                .rotationEffect(.degrees(90))
        }
        .overlay(LinearGradient(colors: [.black.opacity(0.35), .black.opacity(0.05)], startPoint: .leading, endPoint: .trailing))
    }

    private func stripes(vertical: Bool) -> some View {
        let layout = vertical ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
        return layout { ForEach(Color.rainbow.indices, id: \.self) { Color.rainbow[$0] } }
    }

    @ViewBuilder private var sticker: some View {
        if hasUpdate {
            Starburst(text: "UPDATE", fill: Color(hex: "#E03A3E"), ink: .white)
        } else if state.isOwned {
            PriceTag(text: "OWNED")
        } else if isNew {
            Starburst(text: "NEW!", fill: Color(hex: "#FDE047"), ink: Color(hex: "#B91C1C"))
        } else {
            PriceTag(text: "FREE")
        }
    }

    private var isNew: Bool {
        guard let first = app.releases.last?.date, let date = DateFormatter.catalog.date(from: first) else { return false }
        return Date().timeIntervalSince(date) < 14 * 86_400
    }
}

/// Draws the spine as a side of the box turned away from the viewer. Its near (trailing) edge
/// stays full height at `visibleWidth`, where it meets the front face; its far (leading) edge
/// sits at x = 0, `taper` shorter at the top and the bottom.
struct SpineProjection: GeometryEffect {
    var visibleWidth: CGFloat
    var taper: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Map the unit square onto the quad (Heckbert's square-to-quad).
        let (x0, y0) = (0.0, taper)                        // top far
        let (x1, y1) = (visibleWidth, 0.0)                 // top near
        let (x2, y2) = (visibleWidth, size.height)         // bottom near
        let (x3, y3) = (0.0, size.height - taper)          // bottom far
        let dx1 = x1 - x2, dx2 = x3 - x2, dx3 = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, dy3 = y0 - y1 + y2 - y3
        let den = dx1 * dy2 - dx2 * dy1
        let g = (dx3 * dy2 - dx2 * dy3) / den
        let h = (dx1 * dy3 - dx3 * dy1) / den
        let a = x1 - x0 + g * x1, b = x3 - x0 + h * x3
        let d = y1 - y0 + g * y1, e = y3 - y0 + h * y3
        // Fold in the view-to-unit-square scale. SwiftUI multiplies row vectors: [x y 1] · M.
        let sx = 1 / size.width, sy = 1 / size.height
        var m = CATransform3DIdentity
        m.m11 = a * sx; m.m12 = d * sx; m.m14 = g * sx
        m.m21 = b * sy; m.m22 = e * sy; m.m24 = h * sy
        m.m41 = x0;     m.m42 = y0;     m.m44 = 1
        return ProjectionTransform(m)
    }
}

extension DateFormatter {
    static let catalog: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

struct StarShape: Shape {
    var points = 14
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY)
        for i in 0..<(points * 2) {
            let radius = (i.isMultiple(of: 2) ? 1.0 : 0.78) * min(r.width, r.height) / 2
            let a = Double(i) * .pi / Double(points) - .pi / 2
            let pt = CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }
}

struct Starburst: View {
    let text: String
    let fill: Color
    let ink: Color

    var body: some View {
        Text(text)
            .font(.custom("Futura-CondensedExtraBold", fixedSize: 13))
            .foregroundStyle(ink)
            .frame(width: 58, height: 58)
            .background(StarShape().fill(fill).shadow(color: .black.opacity(0.35), radius: 2, x: 1, y: 2))
            .rotationEffect(.degrees(14))
    }
}

/// A round orange price sticker, slightly crooked, as if a clerk put it there.
struct PriceTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.custom("Futura-CondensedExtraBold", fixedSize: 12))
            .tracking(0.5)
            .foregroundStyle(.white)
            .frame(width: 46, height: 46)
            .background(
                Circle().fill(Color(hex: "#F5821F"))
                    .overlay(Circle().strokeBorder(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [2, 2])).padding(3))
                    .shadow(color: .black.opacity(0.35), radius: 1.5, x: 1, y: 1.5)
            )
            .rotationEffect(.degrees(-12))
    }
}
