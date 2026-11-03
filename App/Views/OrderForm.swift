import PhinTechStoreKit
import AppKit
import SwiftUI

/// The clip-out coupon at the foot of every ad. It carries the release details and the install button.
struct OrderForm: View {
    let app: StoreApp
    @ObservedObject var installer: Installer

    @State private var chosen: CatalogFile.Release?
    @State private var copied = false

    private var release: CatalogFile.Release? { chosen ?? app.latest }
    private var state: InstallState { installer.state(for: app) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("✂︎").font(.system(size: 18)).foregroundStyle(Color.ink.opacity(0.6))
                Text("Free Software Order Form")
                    .font(Typeface.garamond(24, "Bold"))
                Spacer()
                Text("NO POSTAGE NECESSARY")
                    .font(.custom("Futura-Bold", fixedSize: 9)).tracking(1.5)
                    .foregroundStyle(Color.ink.opacity(0.7))
            }
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 6) {
                    field("Product", app.title)
                    field("Version", release.map { "v" + $0.version } ?? "—", menu: app.releases.count > 1)
                    field("Released", release.map { longDate($0.date) } ?? "—")
                    field("Size", release.map { ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file) } ?? "—")
                    field("Price", "FREE")
                    if let sha = release?.sha256 {
                        field("Checksum", String(sha.prefix(16)) + "…", mono: true)
                            .help("SHA-256 \(sha)")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    action
                    if let how = app.how {
                        Text(howText(how))
                            .font(Typeface.garamond(14))
                            .fixedSize(horizontal: false, vertical: true)
                        if let command = firstCommand(how) {
                            Button(copied ? "Copied" : "Copy the install command") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(command, forType: .string)
                                copied = true
                            }
                            .buttonStyle(RetroButtonStyle(prominent: false))
                        }
                    } else if app.isMacApp {
                        Text("The store unpacks the app, checks it against its published checksum and puts it in your Applications folder. An older copy goes to the Trash.")
                            .font(Typeface.garamond(13.5, "Italic"))
                            .foregroundStyle(Color.ink.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let source = app.source {
                        Link("Source: \(source.host() ?? "")\(source.path())", destination: source)
                            .font(Typeface.garamond(13.5))
                            .foregroundStyle(Color(hex: "#9A3412"))
                    }
                }
                .frame(width: 330, alignment: .leading)
            }
        }
        .foregroundStyle(Color.ink)
        .padding(22)
        .background(Color.white.opacity(0.35))
        .overlay(Rectangle().strokeBorder(Color.ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [7, 5])))
    }

    // MARK: - Pieces

    @ViewBuilder private var action: some View {
        switch state {
        case .downloading(let p):
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading… \(Int(p * 100))%").font(Typeface.garamond(15, "SemiBold"))
                PlatinumProgress(value: p)
            }
        case .verifying:
            busy("Checking the checksum…")
        case .installing:
            busy("Putting it in Applications…")
        case .installed(let version, let url):
            HStack(spacing: 10) {
                if let r = release, r.version.compare(version, options: .numeric) == .orderedDescending {
                    Button("Update to v\(r.version)") { installer.install(app, release: r) }
                        .buttonStyle(RetroButtonStyle(prominent: true))
                }
                Button("Open \(app.title)") { installer.open(app) }
                    .buttonStyle(RetroButtonStyle(prominent: !(installer.hasUpdate(app))))
            }
            Text("v\(version) is installed in \(url.deletingLastPathComponent().path).")
                .font(Typeface.garamond(13.5, "Italic"))
        case .downloaded(let url):
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                .buttonStyle(RetroButtonStyle(prominent: true))
            Text("Saved to \(url.deletingLastPathComponent().lastPathComponent), checksum verified.")
                .font(Typeface.garamond(13.5, "Italic"))
        case .failed(let message):
            Button("Try Again") { installer.install(app, release: release) }
                .buttonStyle(RetroButtonStyle(prominent: true))
            Text(message).font(Typeface.garamond(13.5, "Italic")).foregroundStyle(Color(hex: "#B91C1C"))
                .fixedSize(horizontal: false, vertical: true)
        case .notInstalled:
            Button(app.isMacApp ? "Install \(app.title)" : "Download the Zip") { installer.install(app, release: release) }
                .buttonStyle(RetroButtonStyle(prominent: true))
        }
    }

    private func busy(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(Typeface.garamond(15, "SemiBold"))
            PlatinumProgress(value: nil)
        }
    }

    private func field(_ label: String, _ value: String, mono: Bool = false, menu: Bool = false) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(label.uppercased())
                .font(.custom("Futura-Medium", fixedSize: 9.5)).tracking(1.2)
                .frame(width: 70, alignment: .leading)
            Group {
                if menu {
                    Menu {
                        ForEach(app.releases, id: \.self) { r in
                            Button("v\(r.version) · \(r.date)") { chosen = r }
                        }
                    } label: {
                        Text(value).font(Typeface.garamond(17, "SemiBold")).foregroundStyle(Color.ink)
                    }
                    .menuStyle(.borderlessButton)
                    .tint(Color.ink)
                    .fixedSize()
                    .help("Choose an older version")
                } else {
                    Text(value)
                        .font(mono ? .system(size: 12, design: .monospaced) : Typeface.garamond(17, "SemiBold"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.ink.opacity(0.4)).frame(height: 0.6).offset(y: 3) }
        }
    }

    private func longDate(_ s: String) -> String {
        guard let d = DateFormatter.catalog.date(from: s) else { return s }
        return d.formatted(date: .long, time: .omitted)
    }

    private func howText(_ how: String) -> AttributedString {
        (try? AttributedString(markdown: how)) ?? AttributedString(how)
    }

    private func firstCommand(_ how: String) -> String? {
        guard let start = how.firstIndex(of: "`") else { return nil }
        let rest = how[how.index(after: start)...]
        guard let end = rest.firstIndex(of: "`") else { return nil }
        return String(rest[..<end])
    }
}

/// A raised, rounded Platinum-era push button.
struct RetroButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typeface.garamond(16, "Bold"))
            .foregroundStyle(prominent ? Color.white : Color.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(prominent
                          ? LinearGradient(colors: [Color(hex: "#3B6FD6"), Color(hex: "#1D3F8F")], startPoint: .top, endPoint: .bottom)
                          : LinearGradient(colors: [Color(hex: "#F2F2F2"), Color(hex: "#C9C9C9")], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.black.opacity(0.8), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.white.opacity(configuration.isPressed ? 0 : 0.5), lineWidth: 1).padding(1.5))
                    .brightness(configuration.isPressed ? -0.15 : 0)
            )
            .shadow(color: .black.opacity(0.3), radius: 0, x: 1, y: 1.5)
            .contentShape(Rectangle())
    }
}

/// A Mac OS 8-style progress bar: blue-lilac fill, or a striped barber pole while the length is unknown.
struct PlatinumProgress: View {
    let value: Double?

    var body: some View {
        TimelineView(.animation(paused: value != nil)) { t in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(hex: "#D8D8D8"))
                    if let value {
                        Rectangle()
                            .fill(LinearGradient(colors: [Color(hex: "#C7C9F2"), Color(hex: "#6B6FD0"), Color(hex: "#4146A8")], startPoint: .top, endPoint: .bottom))
                            .frame(width: geo.size.width * value)
                    } else {
                        let phase = CGFloat(t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)) * 16
                        Canvas { ctx, size in
                            var x = -16 + phase
                            while x < size.width + 16 {
                                var p = Path()
                                p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + 8, y: 0))
                                p.addLine(to: CGPoint(x: x + 16, y: 0)); p.addLine(to: CGPoint(x: x + 8, y: size.height))
                                ctx.fill(p, with: .color(Color(hex: "#6B6FD0")))
                                x += 16
                            }
                        }
                    }
                }
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.8), lineWidth: 1))
            }
        }
        .frame(height: 12)
    }
}
