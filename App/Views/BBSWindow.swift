import SwiftUI
import WebKit

/// The Phin Tech BBS window: the real board at bbs.phin.tech, through its browser terminal (ENiGMA½'s enig-term,
/// which connects over wss://bbs.phin.tech/wss). Opened by phin-tech-bbs:// links and Help ▸ Dial the Phin Tech BBS.
/// The board itself is phin-tech/phin-tech-bbs.
struct BBSWindow: View {
    static let board = URL(string: "https://bbs.phin.tech/_enig/ws-term/")!

    var body: some View {
        BBSWebView(url: Self.board)
            .background(Color.black)
            .navigationTitle("Phin Tech BBS")
    }
}

/// A plain web view for the board. Links that lead off bbs.phin.tech open in the default browser instead.
private struct BBSWebView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")   // black behind the page while it loads, not white
        view.load(URLRequest(url: url))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if let target = action.request.url, action.navigationType == .linkActivated,
               target.host != BBSWindow.board.host {
                NSWorkspace.shared.open(target)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.window?.makeFirstResponder(webView)   // keys go to the board straight away
        }
    }
}
