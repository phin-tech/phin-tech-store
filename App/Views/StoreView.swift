import AppKit
import PhinTechStoreKit
import SwiftUI

@MainActor
final class StoreModel: ObservableObject {
    @Published var shelves: [Shelf] = CatalogLoader.cached() ?? []
    @Published var loading = false
    @Published var error: String?

    var apps: [StoreApp] { shelves.flatMap(\.apps) }

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            shelves = try await CatalogLoader.fetch()
            error = nil
        } catch {
            self.error = shelves.isEmpty
                ? "The store couldn't reach apps.phin.tech. \(error.localizedDescription)"
                : "Showing the shelves from your last visit; apps.phin.tech didn't answer."
        }
    }
}

/// Where the window is: the shelves, or one app's ad. Menu commands drive it too.
@MainActor
final class Router: ObservableObject {
    @Published var path: [StoreApp] = []

    var showingApp: StoreApp? { path.last }
    func back() { if !path.isEmpty { path.removeLast() } }
    func shelves() { path.removeAll() }
    func open(_ app: StoreApp) { path = [app] }
}

struct RootView: View {
    @ObservedObject var store: StoreModel
    @ObservedObject var installer: Installer
    @ObservedObject var router: Router

    var body: some View {
        NavigationStack(path: $router.path) {
            StoreView(store: store, installer: installer) { router.open($0) }
                .navigationDestination(for: StoreApp.self) { app in
                    AdPageView(app: app, installer: installer)
                        .navigationTitle(AdCopy.for(app).title ?? app.title)
                }
                .navigationTitle("Phin Tech Store")
        }
        .task {
            installer.refresh(store.apps)
            async let content: Void = StoreContent.shared.refresh()
            await store.reload()
            installer.refresh(store.apps)
            await content
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            installer.refresh(store.apps)
        }
    }
}

struct StoreView: View {
    @ObservedObject var store: StoreModel
    @ObservedObject var installer: Installer
    let open: (StoreApp) -> Void

    var body: some View {
        GeometryReader { geo in
        ScrollView {
            VStack(spacing: 0) {
                StoreSign()
                if let error = store.error {
                    Text(error)
                        .font(Typeface.garamond(15, "Italic"))
                        .foregroundStyle(Color.paper)
                        .padding(.vertical, 8)
                }
                if store.shelves.isEmpty && store.loading {
                    ProgressView().controlSize(.large).padding(60)
                }
                ForEach(store.shelves) { shelf in
                    ShelfView(shelf: shelf, width: geo.size.width, installer: installer, open: open)
                }
                Text("Every package is free. Every download is checked against its published SHA-256.")
                    .font(Typeface.garamond(14, "Italic"))
                    .foregroundStyle(Color.paper.opacity(0.7))
                    .padding(.vertical, 30)
            }
            .frame(maxWidth: .infinity)
        }
        }
        .background { WoodWall() }
    }
}

/// Dark oak paneling with a little warm light falling from above.
struct WoodWall: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.16, green: 0.09, blue: 0.05)
                if let wall = Art.image("wood-wall") {
                    Image(nsImage: wall).resizable().scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height).clipped()
                }
                RadialGradient(colors: [.clear, .black.opacity(0.55)], center: .top,
                               startRadius: geo.size.width * 0.2, endRadius: geo.size.width * 0.9)
            }
        }
        .ignoresSafeArea()
    }
}

/// The header: a photograph of the shop with a carved and gilded sign hung over it.
struct StoreSign: View {
    var body: some View {
        ZStack {
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 14) {
                    PepperMark(size: 96)
                    Text("The Phin Tech Software Store")
                        .font(Typeface.garamond(46, "ExtraBold"))
                        .tracking(-0.8)
                        .foregroundStyle(LinearGradient(colors: [Color(hex: "#F7E3A3"), Color(hex: "#C99A3D"), Color(hex: "#8A6420")],
                                                        startPoint: .top, endPoint: .bottom))
                        .shadow(color: .black.opacity(0.8), radius: 0, x: 1, y: 2)
                }
                Text("Fine software for the personal computer · Free for the asking")
                    .font(Typeface.garamond(18, "Italic"))
                    .foregroundStyle(Color.paper.opacity(0.9))
                HotlineLine()
            }
            .padding(.horizontal, 34)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(red: 0.22, green: 0.11, blue: 0.05).opacity(0.86))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.brass, lineWidth: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.brass.opacity(0.4), lineWidth: 1).padding(6))
                    .shadow(color: .black.opacity(0.6), radius: 12, y: 8)
            )
        }
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity, minHeight: 260)
        .background {
            if let front = Art.image("store-front") {
                Image(nsImage: front).resizable().scaledToFill()
                    .overlay(LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom))
            }
        }
        .clipped()
        .padding(.bottom, 20)
    }
}

struct ShelfView: View {
    let shelf: Shelf
    let width: CGFloat
    @ObservedObject var installer: Installer
    let open: (StoreApp) -> Void

    private let boxWidth: CGFloat = 168
    private let gap: CGFloat = 46

    private var rows: [[StoreApp]] {
        let perRow = max(1, Int((width - 112 + gap) / (boxWidth * 1.1 + gap)))
        return stride(from: 0, to: shelf.apps.count, by: perRow).map { Array(shelf.apps[$0..<min($0 + perRow, shelf.apps.count)]) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                VStack(spacing: 0) {
                    HStack(alignment: .bottom, spacing: gap) {
                        ForEach(row) { app in
                            Button { open(app) } label: {
                                SoftwareBox(app: app, state: installer.state(for: app),
                                            hasUpdate: installer.hasUpdate(app), width: boxWidth)
                            }
                            .buttonStyle(.plain)
                            .help(app.summary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 56)
                    .padding(.top, 44)
                    .padding(.bottom, -4)
                    .zIndex(1)
                    Plank(label: i == 0 ? shelf.name : nil)
                }
            }
        }
        .padding(.bottom, 26)
    }
}

/// A walnut shelf: a lit top surface, a front lip and a brass name plate.
struct Plank: View {
    let label: String?

    var body: some View {
        VStack(spacing: 0) {
            // Top surface, seen from slightly above.
            wood
                .frame(height: 14)
                .overlay(LinearGradient(colors: [.black.opacity(0.45), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
            // Front lip.
            wood
                .frame(height: 30)
                .overlay(LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.25)).frame(height: 1) }
                .overlay { if let label { NamePlate(text: label) } }
        }
        .padding(.horizontal, 20)
        .shadow(color: .black.opacity(0.7), radius: 10, y: 12)
    }

    private var wood: some View {
        GeometryReader { g in
            if let image = Art.image("wood-shelf") {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: g.size.width, height: g.size.height, alignment: .top).clipped()
            } else {
                Color(red: 0.45, green: 0.26, blue: 0.12)
            }
        }
    }
}

struct NamePlate: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.custom("Copperplate-Bold", fixedSize: 12))
            .tracking(2.5)
            .foregroundStyle(Color(red: 0.25, green: 0.16, blue: 0.05))
            .shadow(color: .white.opacity(0.5), radius: 0, x: 0, y: 1)
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient(colors: [Color(hex: "#F3DB9B"), Color(hex: "#C79A45"), Color(hex: "#9C7228")], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .leading) { Screw().padding(.leading, 5) }
                    .overlay(alignment: .trailing) { Screw().padding(.trailing, 5) }
                    .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
            )
    }
}

private struct Screw: View {
    var body: some View {
        Circle().fill(Color(hex: "#7A5A20")).frame(width: 4, height: 4)
            .overlay(Rectangle().fill(.black.opacity(0.5)).frame(width: 3, height: 0.7))
    }
}

/// "The Phin Tech Hotline: +1 (833) 401-2219 · hotline.phin.tech", in brass under the sign's subtitle.
struct HotlineLine: View {
    @ObservedObject private var content = StoreContent.shared

    var body: some View {
        if let line = content.hotline {
            HStack(spacing: 8) {
                Text("THE PHIN TECH HOTLINE")
                    .font(.custom("Futura-Bold", fixedSize: 10)).tracking(1.8)
                    .foregroundStyle(Color.brass)
                Link(line.number, destination: line.dial)
                    .font(.custom("Futura-Bold", fixedSize: 13)).tracking(1)
                    .help("Call the hotline")
                if let page = line.page, let name = line.pageName {
                    Text("·").foregroundStyle(Color.brass)
                    Link(name, destination: page)
                        .font(.custom("Futura-Bold", fixedSize: 13)).tracking(1)
                }
            }
            .foregroundStyle(Color(hex: "#F7E3A3"))
            .tint(Color(hex: "#F7E3A3"))
            .padding(.top, 4)
        }
    }
}
