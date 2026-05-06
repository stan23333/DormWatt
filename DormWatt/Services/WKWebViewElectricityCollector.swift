//
//  WKWebViewElectricityCollector.swift
//  DormWatt
//

import Foundation
import WebKit

@MainActor
final class WKWebViewElectricityCollector: NSObject, ElectricityCollector, WKNavigationDelegate {
    private let parser: BalanceParser
    private var continuation: CheckedContinuation<Void, Error>?

    init(parser: BalanceParser = RegexBalanceParser()) {
        self.parser = parser
        super.init()
    }

    func collectBalance(
        settings: AppSettings,
        password: String,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws -> ElectricityRecord {
        try validate(settings: settings, password: password)
        logDidAppend?("Collector initialized.")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self

        guard let loginURL = validWebURL(from: settings.loginURL) else {
            throw DormWattError.invalidLoginURL
        }

        stateDidChange?(.loadingLoginPage)
        logDidAppend?("Loading entry URL: \(loginURL.absoluteString)")
        try await load(loginURL, in: webView)
        try await waitForMeaningfulPage(in: webView, logDidAppend: logDidAppend)
        logDidAppend?("Loaded: \(currentPageSummary(in: webView))")

        try await reachPaymentHome(settings: settings, password: password, in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend)

        let balancePageURL = settings.balancePageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !balancePageURL.isEmpty {
            guard let url = validWebURL(from: balancePageURL) else {
                throw DormWattError.invalidLoginURL
            }

            stateDidChange?(.navigatingToBalancePage)
            logDidAppend?("Loading configured balance URL: \(url.absoluteString)")
            try await load(url, in: webView)
            try await waitForMeaningfulPage(in: webView, logDidAppend: logDidAppend)
            logDidAppend?("Loaded configured balance URL: \(currentPageSummary(in: webView))")
        }

        stateDidChange?(.selectingService)
        try await openElectricityPage(settings: settings, in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend)
        try await waitForElement(selector: settings.balanceTextSelector, in: webView, timeoutSeconds: 15, logDidAppend: logDidAppend)

        stateDidChange?(.extractingBalance)
        logDidAppend?("Extracting text from selector: \(settings.balanceTextSelector)")
        let extractedText = try await extractText(selector: settings.balanceTextSelector, in: webView)
        let trimmedText = extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
        logDidAppend?("Extracted text: \(trimmedText)")
        guard !trimmedText.isEmpty else {
            throw DormWattError.emptyExtractedText
        }

        let balance = try parser.parseBalance(from: trimmedText)
        let record = ElectricityRecord(balance: balance, rawText: trimmedText, timestamp: Date())
        stateDidChange?(.success)
        return record
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.resumeNavigation()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.resumeNavigation(error: error)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.resumeNavigation(error: error)
        }
    }

    private func validate(settings: AppSettings, password: String) throws {
        guard validWebURL(from: settings.loginURL) != nil else {
            throw DormWattError.invalidLoginURL
        }

        let requiredValues = [
            settings.loginURL,
            settings.username,
            settings.usernameSelector,
            settings.passwordSelector,
            settings.loginButtonSelector
        ]

        guard requiredValues.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DormWattError.missingRequiredSettings
        }

        guard !password.isEmpty else {
            throw DormWattError.missingPassword
        }
    }

    private func openElectricityPage(
        settings: AppSettings,
        in webView: WKWebView,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws {
        logDidAppend?("Opening life payment section from: \(currentPageSummary(in: webView))")
        logDidAppend?("Before life payment click snapshot: \(try await pageSnapshot(in: webView))")

        let clickedLifeTab = try await clickIfPresent(selector: "#hyper_8", in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend)
        if !clickedLifeTab {
            _ = try await clickIfPresent(text: "生活缴费", in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend)
        }
        logDidAppend?("After life payment click snapshot: \(try await pageSnapshot(in: webView))")

        if try await waitForOptionalElement(selector: "#life_ElecRoom", in: webView, timeoutSeconds: 12, logDidAppend: logDidAppend) {
            logDidAppend?("Found #life_ElecRoom, clicking electricity room entry.")
            _ = try await clickIfPresent(selector: "#life_ElecRoom", in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend)
            logDidAppend?("After #life_ElecRoom click snapshot: \(try await pageSnapshot(in: webView))")
            return
        }

        if try await navigateLifeFrameToElectricityPage(in: webView, logDidAppend: logDidAppend) {
            logDidAppend?("After iframe electricity navigation snapshot: \(try await pageSnapshot(in: webView))")
            return
        }

        let fallbackURL = settings.balancePageURL.isEmpty ? settings.loginURL : settings.balancePageURL
        guard let lifeInfoURL = URL(string: fallbackURL) else {
            throw DormWattError.invalidLoginURL
        }

        stateDidChange?(.selectingService)
        logDidAppend?("Did not find #life_ElecRoom. Loading fallback URL: \(fallbackURL)")
        try await load(lifeInfoURL, in: webView)
        try await waitForMeaningfulPage(in: webView, logDidAppend: logDidAppend)
        logDidAppend?("Loaded fallback electricity page: \(currentPageSummary(in: webView))")
        logDidAppend?("Fallback page snapshot: \(try await pageSnapshot(in: webView))")
    }

    private func reachPaymentHome(
        settings: AppSettings,
        password: String,
        in webView: WKWebView,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws {
        for attempt in 1...6 {
            try await waitForMeaningfulPage(in: webView, logDidAppend: logDidAppend)
            logDidAppend?("Home reach attempt \(attempt): \(currentPageSummary(in: webView))")

            if try await hasElement(selector: "#hyper_8", in: webView) {
                logDidAppend?("Payment home detected via #hyper_8.")
                return
            }

            if isCASLoginURL(webView.url) {
                if try await loginIfNeeded(settings: settings, password: password, in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend) {
                    continue
                }

                logDidAppend?("CAS URL detected but login form was not usable. Snapshot: \(try await pageSnapshot(in: webView))")
                try await Task.sleep(nanoseconds: 1_000_000_000)
                continue
            }

            if try await clickCampusLoginIfNeeded(in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend) {
                continue
            }

            logDidAppend?("No known login/home action available. Snapshot: \(try await pageSnapshot(in: webView))")
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }

        logDidAppend?("Could not reach payment home. Final snapshot: \(try await pageSnapshot(in: webView))")
        throw DormWattError.missingElement("#hyper_8")
    }

    private func loginIfNeeded(
        settings: AppSettings,
        password: String,
        in webView: WKWebView,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws -> Bool {
        let usernameCandidates = [
            settings.usernameSelector,
            "input[type='text']",
            "#username",
            "input#username",
            "input[name='username']"
        ]

        let passwordCandidates = [
            settings.passwordSelector,
            "input[type='password']",
            "#password",
            "input#password",
            "input[name='password']"
        ]

        guard let usernameSelector = try await firstVisibleEditableSelector(from: usernameCandidates, in: webView),
              let passwordSelector = try await firstVisibleEditableSelector(from: passwordCandidates, in: webView) else {
            logDidAppend?("CAS login form not present on current page.")
            return false
        }

        logDidAppend?("CAS login form detected. usernameSelector=\(usernameSelector), passwordSelector=\(passwordSelector)")
        stateDidChange?(.fillingCredentials)
        try await fill(selector: usernameSelector, value: settings.username, in: webView)
        try await fill(selector: passwordSelector, value: password, in: webView)

        stateDidChange?(.submittingLogin)
        let beforeLoginURL = webView.url?.absoluteString ?? ""
        try await clickLoginButton(configuredSelector: settings.loginButtonSelector, in: webView, logDidAppend: logDidAppend)
        try await waitForPostLoginProgress(from: beforeLoginURL, passwordCandidates: passwordCandidates, in: webView, logDidAppend: logDidAppend)
        try await waitForMeaningfulPage(in: webView, logDidAppend: logDidAppend)
        logDidAppend?("After login click: \(currentPageSummary(in: webView))")
        return true
    }

    private func clickCampusLoginIfNeeded(
        in webView: WKWebView,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws -> Bool {
        if isCASLoginURL(webView.url) {
            logDidAppend?("Already on CAS login page. Skipping campus-login link click.")
            return false
        }

        let selectors = [
            "a[href$='CasLogin.aspx']",
            "a[href='CasLogin.aspx']",
            "a[href*='/cas/login']"
        ]

        for selector in selectors {
            if try await clickIfPresent(selector: selector, in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend) {
                try await waitForMeaningfulPage(in: webView, logDidAppend: logDidAppend)
                return true
            }
        }

        for text in ["校内师生登录", "统一身份认证登录"] {
            if try await clickIfPresent(text: text, in: webView, stateDidChange: stateDidChange, logDidAppend: logDidAppend) {
                try await waitForMeaningfulPage(in: webView, logDidAppend: logDidAppend)
                return true
            }
        }

        return false
    }

    private func firstExistingSelector(from candidates: [String], in webView: WKWebView) async throws -> String? {
        for candidate in candidates {
            let selector = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !selector.isEmpty else {
                continue
            }
            if try await hasElement(selector: selector, in: webView) {
                return selector
            }
        }
        return nil
    }

    private func firstVisibleEditableSelector(from candidates: [String], in webView: WKWebView) async throws -> String? {
        let cleanedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let script = """
        (() => {
          \(documentCollectorScript)
          const selectors = \(javaScriptArrayLiteral(cleanedCandidates));
          function isVisibleEditable(element) {
            const view = element.ownerDocument.defaultView || window;
            const style = view.getComputedStyle(element);
            const rect = element.getBoundingClientRect();
            const visible = rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none";
            const editable = !element.disabled && !element.readOnly && (element.matches("input, textarea") || element.isContentEditable);
            return visible && editable;
          }
          for (const selector of selectors) {
            for (const doc of collectDocuments()) {
              const element = Array.from(doc.querySelectorAll(selector)).find(isVisibleEditable);
              if (element) { return selector; }
            }
          }
          return null;
        })();
        """

        return try await evaluate(script, in: webView) as? String
    }

    private func load(_ url: URL, in webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.load(URLRequest(url: url))
        }
    }

    private func resumeNavigation(error: Error? = nil) {
        if let error {
            continuation?.resume(throwing: DormWattError.navigationFailure(error.localizedDescription))
        } else {
            continuation?.resume()
        }
        continuation = nil
    }

    private func fill(selector: String, value: String, in webView: WKWebView) async throws {
        let script = """
        (() => {
          \(documentCollectorScript)
          const selector = \(javaScriptLiteral(selector));
          const value = \(javaScriptLiteral(value));
          const element = collectDocuments().map(doc => doc.querySelector(selector)).find(Boolean);
          if (!element) { throw new Error("Missing element: " + selector); }
          element.focus();
          element.value = value;
          element.dispatchEvent(new Event("input", { bubbles: true }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          return true;
        })();
        """
        _ = try await evaluate(script, in: webView)
    }

    private func click(selector: String, in webView: WKWebView) async throws {
        let script = """
        (() => {
          \(documentCollectorScript)
          const selector = \(javaScriptLiteral(selector));
          const element = collectDocuments().map(doc => doc.querySelector(selector)).find(Boolean);
          if (!element) { throw new Error("Missing element: " + selector); }
          element.click();
          return true;
        })();
        """
        _ = try await evaluate(script, in: webView)
    }

    private func clickLoginButton(
        configuredSelector: String,
        in webView: WKWebView,
        logDidAppend: ((String) -> Void)?
    ) async throws {
        let selectorCandidates = [
            configuredSelector,
            "button.login-btn",
            "button.el-button.login-btn",
            "button.el-button--primary.login-btn"
        ]

        if let selector = try await firstExistingSelector(from: selectorCandidates, in: webView) {
            logDidAppend?("Clicking login button selector: \(selector)")
            try await click(selector: selector, in: webView)
            return
        }

        let script = """
        (() => {
          \(documentCollectorScript)
          const candidates = collectDocuments().flatMap(doc => Array.from(doc.querySelectorAll("button, input[type='button'], input[type='submit']")));
          const visibleCandidates = candidates.filter(el => {
            const rect = el.getBoundingClientRect();
            const style = getComputedStyle(el);
            return rect.width > 0 && rect.height > 0 && style.visibility !== "hidden" && style.display !== "none";
          });
          const element = visibleCandidates.find(el => {
            const text = (el.innerText || el.value || el.textContent || "").trim().replace(/\\s+/g, "");
            return text === "登录";
          });
          if (!element) { return false; }
          element.click();
          return true;
        })();
        """

        guard let didClick = try await evaluate(script, in: webView) as? Bool, didClick else {
            throw DormWattError.missingElement(configuredSelector.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        logDidAppend?("Clicked visible login button by text.")
    }

    private func waitForPostLoginProgress(
        from beforeLoginURL: String,
        passwordCandidates: [String],
        in webView: WKWebView,
        logDidAppend: ((String) -> Void)?
    ) async throws {
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 500_000_000)
            while webView.isLoading {
                try await Task.sleep(nanoseconds: 150_000_000)
            }

            let currentURL = webView.url?.absoluteString ?? ""
            if currentURL != beforeLoginURL {
                logDidAppend?("Login advanced URL to: \(currentPageSummary(in: webView))")
                return
            }

            if try await firstVisibleEditableSelector(from: passwordCandidates, in: webView) == nil {
                logDidAppend?("Login form disappeared: \(currentPageSummary(in: webView))")
                return
            }
        }

        logDidAppend?("Login did not visibly advance before timeout: \(currentPageSummary(in: webView))")
    }

    @discardableResult
    private func clickIfPresent(
        text: String,
        in webView: WKWebView,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws -> Bool {
        let script = """
        (() => {
          const targetText = \(javaScriptLiteral(text));
          \(documentCollectorScript)
          const candidates = collectDocuments().flatMap(doc => Array.from(doc.querySelectorAll("a, button, input, div, span, li, td")));
          const element = candidates.find(el => {
            const value = (el.innerText || el.value || el.textContent || "").trim().replace(/\\s+/g, "");
            return value === targetText || value.includes(targetText);
          });
          if (!element) { return false; }
          element.click();
          return true;
        })();
        """

        guard let didClick = try await evaluate(script, in: webView) as? Bool, didClick else {
            logDidAppend?("Text click target not found: \(text)")
            return false
        }

        logDidAppend?("Clicked text target: \(text)")
        stateDidChange?(.selectingService)
        try await waitForPageActivity(in: webView)
        logDidAppend?("After text click: \(currentPageSummary(in: webView))")
        return true
    }

    @discardableResult
    private func clickIfPresent(
        selector: String,
        in webView: WKWebView,
        stateDidChange: ((CollectorState) -> Void)?,
        logDidAppend: ((String) -> Void)?
    ) async throws -> Bool {
        let script = """
        (() => {
          \(documentCollectorScript)
          const element = collectDocuments().map(doc => doc.querySelector(\(javaScriptLiteral(selector)))).find(Boolean);
          if (!element) { return false; }
          element.click();
          return true;
        })();
        """

        guard let didClick = try await evaluate(script, in: webView) as? Bool, didClick else {
            logDidAppend?("Selector click target not found: \(selector)")
            return false
        }

        logDidAppend?("Clicked selector target: \(selector)")
        stateDidChange?(.selectingService)
        try await waitForPageActivity(in: webView)
        logDidAppend?("After selector click: \(currentPageSummary(in: webView))")
        return true
    }

    private func hasElement(selector: String, in webView: WKWebView) async throws -> Bool {
        let script = """
        (() => {
          \(documentCollectorScript)
          return collectDocuments().some(doc => Boolean(doc.querySelector(\(javaScriptLiteral(selector)))));
        })();
        """
        return (try await evaluate(script, in: webView) as? Bool) ?? false
    }

    private func waitForElement(
        selector: String,
        in webView: WKWebView,
        timeoutSeconds: TimeInterval,
        logDidAppend: ((String) -> Void)?
    ) async throws {
        if try await waitForOptionalElement(selector: selector, in: webView, timeoutSeconds: timeoutSeconds, logDidAppend: logDidAppend) {
            return
        }

        let snapshot = try await pageSnapshot(in: webView)
        logDidAppend?("Missing required selector: \(selector)")
        logDidAppend?("Page snapshot: \(snapshot)")
        throw DormWattError.missingElement(selector.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func waitForOptionalElement(
        selector: String,
        in webView: WKWebView,
        timeoutSeconds: TimeInterval,
        logDidAppend: ((String) -> Void)?
    ) async throws -> Bool {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSelector.isEmpty else {
            return true
        }

        logDidAppend?("Waiting up to \(Int(timeoutSeconds))s for selector: \(trimmedSelector)")
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try await hasElement(selector: trimmedSelector, in: webView) {
                logDidAppend?("Found selector: \(trimmedSelector)")
                return true
            }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        logDidAppend?("Timed out waiting for optional selector: \(trimmedSelector)")
        return false
    }

    private func extractText(selector: String, in webView: WKWebView) async throws -> String {
        let trimmedSelector = selector.trimmingCharacters(in: .whitespacesAndNewlines)
        let script: String

        if trimmedSelector.isEmpty {
            script = """
            (() => {
              \(documentCollectorScript)
              return collectDocuments().map(doc => doc.body ? doc.body.innerText : "").filter(Boolean).join("\\n");
            })();
            """
        } else {
            script = """
            (() => {
              const selector = \(javaScriptLiteral(trimmedSelector));
              \(documentCollectorScript)
              const element = collectDocuments().map(doc => doc.querySelector(selector)).find(Boolean);
              if (!element) { throw new Error("Missing element: " + selector); }
              return element.innerText || element.textContent || "";
            })();
            """
        }

        guard let text = try await evaluate(script, in: webView) as? String else {
            throw DormWattError.emptyExtractedText
        }
        return text
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        do {
            return try await webView.evaluateJavaScript(script)
        } catch {
            let nsError = error as NSError
            let message = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
            if message.contains("Missing element") {
                let selector = message.components(separatedBy: "Missing element: ").last ?? message
                throw DormWattError.missingElement(selector)
            }
            throw DormWattError.javaScriptFailure(message)
        }
    }

    private func navigateLifeFrameToElectricityPage(
        in webView: WKWebView,
        logDidAppend: ((String) -> Void)?
    ) async throws -> Bool {
        let script = """
        (() => {
          const frame = document.querySelector("iframe[name='iframe1'], iframe#iframe1, iframe");
          if (!frame) { return "no-frame"; }
          let base = document.baseURI;
          try {
            if (frame.contentDocument && frame.contentDocument.location) {
              base = frame.contentDocument.location.href;
            }
          } catch (_) {}
          const target = new URL("ElecRoomInfo.aspx", base.includes("/modules/life/") ? base : new URL("modules/life/Info.aspx", document.baseURI).href).href;
          frame.src = target;
          return target;
        })();
        """

        guard let result = try await evaluate(script, in: webView) as? String else {
            return false
        }

        guard result != "no-frame" else {
            logDidAppend?("No iframe found for direct electricity navigation.")
            return false
        }

        logDidAppend?("Navigating iframe directly to: \(result)")
        try await waitForPageActivity(in: webView)
        return true
    }

    private func waitForPageActivity(in webView: WKWebView) async throws {
        try await Task.sleep(nanoseconds: 1_500_000_000)

        while webView.isLoading {
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func waitForMeaningfulPage(
        in webView: WKWebView,
        logDidAppend: ((String) -> Void)?
    ) async throws {
        let deadline = Date().addingTimeInterval(12)
        var lastSummary = currentPageSummary(in: webView)

        while Date() < deadline {
            try await waitForPageActivity(in: webView)
            lastSummary = currentPageSummary(in: webView)

            if try await pageLooksMeaningful(in: webView) {
                return
            }

            try await Task.sleep(nanoseconds: 500_000_000)
        }

        logDidAppend?("Page still looks like a loading shell after wait: \(lastSummary)")
        logDidAppend?("Loading shell snapshot: \(try await pageSnapshot(in: webView))")
    }

    private func pageLooksMeaningful(in webView: WKWebView) async throws -> Bool {
        let script = """
        (() => {
          \(documentCollectorScript)
          const docs = collectDocuments();
          const title = (document.title || "").trim();
          const url = location.href || "";
          const text = docs.map(doc => doc.body ? doc.body.innerText : "").join("\\n").trim();
          const controlCount = docs.reduce((count, doc) => count + doc.querySelectorAll("a, button, input").length, 0);
          if (url.includes("/portal/shortcut.html") && title === "Loading..." && text.replace(/\\s+/g, "") === "Loading..." && controlCount === 0) {
            return false;
          }
          return title !== "Loading..." || controlCount > 0 || text.replace(/\\s+/g, "") !== "Loading...";
        })();
        """
        return (try await evaluate(script, in: webView) as? Bool) ?? true
    }

    private func currentPageSummary(in webView: WKWebView) -> String {
        let title = webView.title ?? "(no title)"
        let url = webView.url?.absoluteString ?? "(no url)"
        return "title=\(title), url=\(url)"
    }

    private func isCASLoginURL(_ url: URL?) -> Bool {
        guard let absoluteString = url?.absoluteString.lowercased() else {
            return false
        }
        return absoluteString.contains("/cas/login")
    }

    private func pageSnapshot(in webView: WKWebView) async throws -> String {
        let script = """
        (() => {
          \(documentCollectorScript)
          const frameInfo = Array.from(document.querySelectorAll("iframe")).map((frame, index) => {
            const id = frame.id ? "#" + frame.id : "";
            const name = frame.name ? " name=" + frame.name : "";
            const src = frame.src || frame.getAttribute("src") || "";
            return "IFRAME[" + index + "]" + id + name + " src=" + src;
          }).join("\\n");
          const docs = collectDocuments().map((doc, index) => {
            const title = doc.title || "";
            const url = doc.location ? doc.location.href : "";
            const text = (doc.body ? doc.body.innerText : "").trim().replace(/\\s+/g, " ").slice(0, 700);
            const controls = Array.from(doc.querySelectorAll("a, button, input")).slice(0, 30).map(el => {
              const id = el.id ? "#" + el.id : "";
              const href = el.getAttribute("href") || "";
              const placeholder = el.getAttribute("placeholder") || "";
              const label = (el.innerText || el.value || "").trim().replace(/\\s+/g, " ").slice(0, 50);
              return [el.tagName.toLowerCase() + id, placeholder, href, label].filter(Boolean).join(" | ");
            }).join("; ");
            return "DOC[" + index + "] title=" + title + " url=" + url + " text=" + text + " controls=" + controls;
          }).join("\\n");
          return [frameInfo, docs].filter(Boolean).join("\\n");
        })();
        """

        return (try await evaluate(script, in: webView) as? String) ?? "No snapshot."
    }

    private var documentCollectorScript: String {
        """
        function collectDocuments() {
          const docs = [];
          const seen = new Set();
          function visit(doc) {
            if (!doc || seen.has(doc)) { return; }
            seen.add(doc);
            docs.push(doc);
            Array.from(doc.querySelectorAll("iframe")).forEach(frame => {
              try { visit(frame.contentDocument); } catch (_) {}
            });
          }
          visit(document);
          return docs;
        }
        """
    }

    private func javaScriptLiteral(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let literal = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return literal
    }

    private func javaScriptArrayLiteral(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let literal = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return literal
    }

    private func validWebURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
    }
}
