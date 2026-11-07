import SwiftUI
import WebKit

/// An HTML email as its sender designed it (a Google Classroom notice, a newsletter…),
/// on a white card. JavaScript is off, nothing is stored between emails, and clicking a
/// link hands it to `openLink` (Chrome) instead of navigating inside the notch.
struct EmailWebView: NSViewRepresentable {
    let html: String
    let openLink: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(openLink: openLink)
    }

    func makeNSView(context: Context) -> EmailWKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = EmailWKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        // Emails are designed for a light page, whatever the notch looks like.
        webView.appearance = NSAppearance(named: .aqua)
        webView.wantsLayer = true
        webView.layer?.cornerRadius = 10
        webView.layer?.masksToBounds = true
        return webView
    }

    func updateNSView(_ webView: EmailWKWebView, context: Context) {
        context.coordinator.openLink = openLink
        guard context.coordinator.shownHTML != html else { return }
        context.coordinator.shownHTML = html
        webView.pageZoom = 1
        webView.loadHTMLString(EmailWebView.page(for: html), baseURL: nil)
    }

    /// The email with a few defaults ahead of its own styles: white page, readable text,
    /// images no wider than the card.
    static func page(for html: String) -> String {
        let defaults = """
        <meta charset="utf-8"><meta name="color-scheme" content="light">
        <style>
        html { background: #ffffff; }
        body { margin: 0; padding: 14px 16px; color: #1d1d1f; font: 14px/1.45 -apple-system, Helvetica, sans-serif; overflow-wrap: break-word; }
        img { max-width: 100%; height: auto; }
        </style>
        """
        if let head = html.range(of: "<head", options: .caseInsensitive),
           let close = html[head.upperBound...].firstIndex(of: ">") {
            var page = html
            page.insert(contentsOf: defaults, at: page.index(after: close))
            return page
        }
        return "<!DOCTYPE html><html><head>\(defaults)</head><body>\(html)</body></html>"
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var openLink: (URL) -> Void
        var shownHTML: String?

        init(openLink: @escaping (URL) -> Void) {
            self.openLink = openLink
        }

        // Only the email itself loads in the card; clicked links go to the browser.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if url.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            if navigationAction.navigationType == .linkActivated {
                openLink(url)
            }
            decisionHandler(.cancel)
        }

        // Emails built for a wider screen (most are 600px) are scaled down to fit the card.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let measure = "Math.max(document.documentElement.scrollWidth, document.body ? document.body.scrollWidth : 0)"
            webView.evaluateJavaScript(measure, in: nil, in: .defaultClient) { result in
                guard case .success(let value) = result,
                      let width = (value as? NSNumber)?.doubleValue, width > 0 else { return }
                let available = Double(webView.bounds.width)
                if available > 0, width > available + 1 {
                    webView.pageZoom = CGFloat(max(0.5, available / width))
                }
            }
        }
    }
}

/// Takes the first click even while the notch isn't the focused window.
final class EmailWKWebView: WKWebView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
