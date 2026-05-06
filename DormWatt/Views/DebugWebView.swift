//
//  DebugWebView.swift
//  DormWatt
//

import SwiftUI
import WebKit

struct DebugWebViewScreen: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    @State private var address = ""
    @State private var currentURL = ""
    @State private var pageTitle = ""
    @State private var pageScan = "Open a page, then scan it to inspect fields and buttons."
    @State private var command = DebugWebCommand()

    private var initialURL: String {
        settingsViewModel.loginURL.isEmpty
            ? "https://example.com/login"
            : settingsViewModel.loginURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    command = DebugWebCommand(action: .back)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")

                Button {
                    command = DebugWebCommand(action: .forward)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Forward")

                Button {
                    command = DebugWebCommand(action: .reload)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload")

                TextField("URL", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        openAddress()
                    }

                Button("Open") {
                    openAddress()
                }

                Button {
                    command = DebugWebCommand(action: .scan)
                } label: {
                    Image(systemName: "magnifyingglass")
                    Text("Scan Page")
                }
            }
            .padding()

            Divider()

            #if os(macOS)
            HSplitView {
                debugWebView
                    .frame(minWidth: 420)
                scanPanel
                    .frame(minWidth: 300, idealWidth: 380)
            }
            #else
            VStack(spacing: 0) {
                debugWebView
                    .frame(minHeight: 420)
                Divider()
                scanPanel
                    .frame(minHeight: 220)
            }
            #endif
        }
        .onAppear {
            if address.isEmpty {
                address = initialURL
            }
        }
        .onChange(of: currentURL) { newValue in
            if !newValue.isEmpty {
                address = newValue
            }
        }
    }

    private func openAddress() {
        command = DebugWebCommand(action: .open(address))
    }

    private var debugWebView: some View {
        DebugWebView(
            initialURLString: initialURL,
            command: command,
            currentURL: $currentURL,
            pageTitle: $pageTitle,
            pageScan: $pageScan
        )
    }

    private var scanPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pageTitle.isEmpty ? "Current Page" : pageTitle)
                    .font(.headline)
                Text(currentURL.isEmpty ? initialURL : currentURL)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }

            Divider()

            ScrollView {
                Text(pageScan)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}

struct DebugWebCommand: Equatable {
    enum Action: Equatable {
        case none
        case open(String)
        case reload
        case back
        case forward
        case scan
    }

    let id = UUID()
    let action: Action

    init(action: Action = .none) {
        self.action = action
    }
}

private let scanPageScript = """
(() => {
  function cssEscape(value) {
    if (window.CSS && CSS.escape) { return CSS.escape(value); }
    return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
  }

  function selectorFor(el) {
    if (el.id) { return "#" + cssEscape(el.id); }
    if (el.name) { return el.tagName.toLowerCase() + "[name='" + String(el.name).replace(/'/g, "\\\\'") + "']"; }
    if (el.getAttribute("placeholder")) { return el.tagName.toLowerCase() + "[placeholder='" + el.getAttribute("placeholder").replace(/'/g, "\\\\'") + "']"; }
    const cls = Array.from(el.classList || []).slice(0, 2).map(cssEscape).join(".");
    if (cls) { return el.tagName.toLowerCase() + "." + cls; }
    return el.tagName.toLowerCase();
  }

  function describe(el, index) {
    const text = (el.innerText || el.value || el.getAttribute("aria-label") || "").trim().replace(/\\s+/g, " ").slice(0, 80);
    const attrs = ["type", "id", "name", "placeholder", "class", "href"]
      .map(name => {
        const value = el.getAttribute(name);
        return value ? name + "=" + JSON.stringify(value) : null;
      })
      .filter(Boolean)
      .join(" ");
    return String(index + 1).padStart(2, "0") + ". " + selectorFor(el) + "\\n    <" + el.tagName.toLowerCase() + (attrs ? " " + attrs : "") + "> " + text;
  }

  const elements = Array.from(document.querySelectorAll("input, button, select, textarea, a"))
    .filter(el => {
      const rect = el.getBoundingClientRect();
      const style = window.getComputedStyle(el);
      return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none";
    });

  const title = document.title || "";
  const url = location.href;
  const bodyHint = (document.body ? document.body.innerText : "").trim().replace(/\\s+/g, " ").slice(0, 500);
  return ["TITLE: " + title, "URL: " + url, "", "VISIBLE CONTROLS:", elements.map(describe).join("\\n"), "", "BODY HINT:", bodyHint].join("\\n");
})();
"""

#if os(macOS)
struct DebugWebView: NSViewRepresentable {
    let initialURLString: String
    let command: DebugWebCommand
    @Binding var currentURL: String
    @Binding var pageTitle: String
    @Binding var pageScan: String

    func makeCoordinator() -> Coordinator {
        Coordinator(currentURL: $currentURL, pageTitle: $pageTitle, pageScan: $pageScan)
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        loadIfNeeded(webView, coordinator: context.coordinator)
        run(command, in: webView, coordinator: context.coordinator)
    }

    private func loadIfNeeded(_ webView: WKWebView, coordinator: Coordinator) {
        guard let url = URL(string: initialURLString), !initialURLString.isEmpty else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            coordinator.loadedURLString = nil
            return
        }

        if coordinator.loadedURLString == nil {
            webView.load(URLRequest(url: url))
            coordinator.loadedURLString = initialURLString
        }
    }

    private func run(_ command: DebugWebCommand, in webView: WKWebView, coordinator: Coordinator) {
        guard coordinator.lastCommandID != command.id else {
            return
        }
        coordinator.lastCommandID = command.id

        switch command.action {
        case .none:
            break
        case let .open(value):
            let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmedValue), !trimmedValue.isEmpty else {
                pageScan = "Invalid URL: \(value)"
                return
            }
            webView.load(URLRequest(url: url))
            coordinator.loadedURLString = trimmedValue
        case .reload:
            webView.reload()
        case .back:
            if webView.canGoBack {
                webView.goBack()
            }
        case .forward:
            if webView.canGoForward {
                webView.goForward()
            }
        case .scan:
            coordinator.scanPage()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var currentURL: String
        @Binding var pageTitle: String
        @Binding var pageScan: String

        var loadedURLString: String?
        var lastCommandID: UUID?
        weak var webView: WKWebView?

        init(currentURL: Binding<String>, pageTitle: Binding<String>, pageScan: Binding<String>) {
            _currentURL = currentURL
            _pageTitle = pageTitle
            _pageScan = pageScan
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            currentURL = webView.url?.absoluteString ?? ""
            pageTitle = webView.title ?? ""
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            pageScan = "Navigation failed: \(error.localizedDescription)"
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            pageScan = "Navigation failed: \(error.localizedDescription)"
        }

        func scanPage() {
            guard let webView else {
                return
            }

            webView.evaluateJavaScript(scanPageScript) { result, error in
                if let error {
                    self.pageScan = "Scan failed: \(error.localizedDescription)"
                } else {
                    self.pageScan = result as? String ?? "No scan result."
                }
                self.currentURL = webView.url?.absoluteString ?? ""
                self.pageTitle = webView.title ?? ""
            }
        }
    }
}
#else
struct DebugWebView: UIViewRepresentable {
    let initialURLString: String
    let command: DebugWebCommand
    @Binding var currentURL: String
    @Binding var pageTitle: String
    @Binding var pageScan: String

    func makeCoordinator() -> Coordinator {
        Coordinator(currentURL: $currentURL, pageTitle: $pageTitle, pageScan: $pageScan)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        guard let url = URL(string: initialURLString), !initialURLString.isEmpty else {
            webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
            context.coordinator.loadedURLString = nil
            return
        }

        if context.coordinator.loadedURLString == nil {
            webView.load(URLRequest(url: url))
            context.coordinator.loadedURLString = initialURLString
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var currentURL: String
        @Binding var pageTitle: String
        @Binding var pageScan: String

        var loadedURLString: String?
        weak var webView: WKWebView?

        init(currentURL: Binding<String>, pageTitle: Binding<String>, pageScan: Binding<String>) {
            _currentURL = currentURL
            _pageTitle = pageTitle
            _pageScan = pageScan
        }
    }
}
#endif
