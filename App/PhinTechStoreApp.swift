import AppKit
import PhinTechStoreKit
import SwiftUI

@main
struct PhinTechStoreApp: App {
    @StateObject private var store = StoreModel()
    @StateObject private var installer = Installer()
    @StateObject private var router = Router()

    init() {
        Typeface.registerFonts()
        #if DEBUG
        DebugDriver.startIfAsked()   // only when launched with DEBUG_SOCKET (`just debug-app`)
        #endif
    }

    var body: some Scene {
        Window("Phin Tech Store", id: "store") {
            RootView(store: store, installer: installer, router: router)
                .frame(minWidth: 960, minHeight: 680)
                .onAppear { startUpdates() }
        }
        .defaultSize(width: 1180, height: 860)
        .commands {
            appMenu
            viewMenu
            storeMenu
            helpMenu
        }
        Settings {
            SettingsView()
        }
    }

    private func startUpdates() {
        #if !APP_STORE
        UpdateChecker.shared.start()
        #endif
    }

    // MARK: - Menus

    /// About, with Pepper and the slogan, and Check for Updates under it.
    @CommandsBuilder private var appMenu: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Phin Tech Store") { AboutPanel.show() }
            #if !APP_STORE
            Button("Check for Updates…") { UpdateChecker.shared.checkForUpdates() }
            #endif
        }
        // One window, so no New Window; ⌘W closes it as usual.
        CommandGroup(replacing: .newItem) {}
    }

    @CommandsBuilder private var viewMenu: some Commands {
        CommandGroup(before: .toolbar) {
            ViewMenuItems(store: store, installer: installer, router: router)
        }
    }

    /// Store: every app on the shelves, plus actions on the one being shown. The items are views, so they follow
    /// the store, the installer and the router as they change; plain command closures would not.
    @CommandsBuilder private var storeMenu: some Commands {
        CommandMenu("Store") {
            StoreMenuItems(store: store, installer: installer, router: router)
        }
    }

    @CommandsBuilder private var helpMenu: some Commands {
        CommandGroup(replacing: .help) {
            Button("Phin Tech Store Help") { NSWorkspace.shared.open(URL(string: "https://github.com/phin-tech/phin-tech-store#readme")!) }
            Button("Visit apps.phin.tech") { NSWorkspace.shared.open(StoreApp.site) }
            HotlineMenuItems()
        }
    }
}

/// The standard About panel, with a line from Pepper.
enum AboutPanel {
    @MainActor static func show() {
        let credits = NSMutableAttributedString(
            string: "Pepper never forgets.\n",
            attributes: [.font: NSFont(name: "EBGaramond-Bold", size: 15) ?? .boldSystemFont(ofSize: 13)])
        credits.append(NSAttributedString(
            string: "Fine software for the personal computer, from apps.phin.tech.",
            attributes: [.font: NSFont(name: "EBGaramond-Italic", size: 13) ?? .systemFont(ofSize: 11),
                         .foregroundColor: NSColor.secondaryLabelColor]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Phin Tech Store", .credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct StoreMenuItems: View {
    @ObservedObject var store: StoreModel
    @ObservedObject var installer: Installer
    @ObservedObject var router: Router

    var body: some View {
        if let app = router.showingApp {
            let state = installer.state(for: app)
            if state.isOwned {
                Button(app.isHerdrMod ? "Open Herdr" : "Open \(app.title)") { installer.open(app) }
                    .keyboardShortcut("o")
                if installer.hasUpdate(app) {
                    Button("Update \(app.title)") { installer.install(app) }
                        .keyboardShortcut("u")
                }
            } else if !app.isListing {
                Button(app.isMacApp ? "Install \(app.title)" : "Download \(app.title)") { installer.install(app) }
                    .keyboardShortcut("i")
                    .disabled(state.isBusy)
            }
            if !app.isListing {  // the download page lists only what it has a download for
                Button("Show on apps.phin.tech") {
                    NSWorkspace.shared.open(URL(string: "https://apps.phin.tech/#\(app.id)")!)
                }
            }
            if let source = app.source {
                Button("View Source") { NSWorkspace.shared.open(source) }
            }
            Divider()
        }
        ForEach(store.shelves) { shelf in
            Section(shelf.name) {
                ForEach(shelf.apps) { app in
                    Button(app.title + (installer.hasUpdate(app) ? " (update)" : "")) { router.open(app) }
                }
            }
        }
        Divider()
        Button("Update All") {
            for app in store.apps where installer.hasUpdate(app) { installer.install(app) }
        }
        .keyboardShortcut("u", modifiers: [.command, .shift])
        .disabled(!store.apps.contains(where: installer.hasUpdate))
    }
}

/// View menu items that depend on where the window is.
private struct ViewMenuItems: View {
    @ObservedObject var store: StoreModel
    @ObservedObject var installer: Installer
    @ObservedObject var router: Router

    var body: some View {
        Button("Back to the Shelves") { router.shelves() }
            .keyboardShortcut("1")
            .disabled(router.path.isEmpty)
        Button("Back") { router.back() }
            .keyboardShortcut("[")
            .disabled(router.path.isEmpty)
        Divider()
        Button("Reload the Shelves") {
            Task {
                async let content: Void = StoreContent.shared.refresh()
                await store.reload()
                installer.refresh(store.apps)
                await content
            }
        }
            .keyboardShortcut("r")
        Divider()
    }
}

/// Help ▸ Call the Phin Tech Hotline (FaceTime or the iPhone place the call) and its web page.
private struct HotlineMenuItems: View {
    @ObservedObject private var content = StoreContent.shared

    var body: some View {
        if let line = content.hotline {
            Divider()
            Button("Call the Phin Tech Hotline: \(line.number)") { NSWorkspace.shared.open(line.dial) }
            if let page = line.page {
                Button("Visit \(line.pageName ?? "the Hotline Page")") { NSWorkspace.shared.open(page) }
            }
        }
    }
}
