import AppKit
import ApplicationServices

// MARK: - Window context capture (M8)

enum WindowContextCapture {

    /// Returns a PromptContext from the given app (typically the last app active before NotchBuddy).
    /// Uses AXUIElement for window title (requires Accessibility permission).
    /// Uses AppleScript for browser URL (Safari, Chrome, Arc, Firefox, Edge).
    static func captureActive(from app: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) -> PromptContext? {
        guard let app, let appName = app.localizedName else { return nil }

        let pid = app.processIdentifier
        let axApp = AXUIElementCreateApplication(pid)
        // This runs on the main thread: a busy or hung app answers within 0.5 s or not at all
        // (0.3.6), instead of the system's default timeout, during which the island froze.
        _ = AXUIElementSetMessagingTimeout(axApp, messagingTimeout)

        // --- Window title ---
        var title = ""
        var windowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
           let windowRef {
            // swiftlint:disable force_cast
            let axWindow = windowRef as! AXUIElement
            _ = AXUIElementSetMessagingTimeout(axWindow, messagingTimeout)
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef) == .success,
               let t = titleRef as? String {
                title = t
            }
        }

        // --- Browser URL ---
        let url = browserURL(for: app)

        return .window(appName: appName, title: title, url: url)
    }

    // MARK: - Private

    /// Seconds an Accessibility read of the captured app may take.
    private static let messagingTimeout: Float = 0.5

    /// Each browser's question, asked with a 2 s limit (0.3.6): a busy or hung browser no longer
    /// holds the main thread for the Apple Event's default 2 min. The first time, macOS's
    /// Automation consent prompt still waits for the user's answer.
    private static let browserScripts: [String: String] = [
        "com.apple.Safari":
            withTimeout("tell application \"Safari\" to return URL of current tab of front window"),
        "com.google.Chrome":
            withTimeout("tell application \"Google Chrome\" to return URL of active tab of front window"),
        "company.thebrowser.Browser":
            withTimeout("tell application \"Arc\" to return URL of active tab of front window"),
        "org.mozilla.firefox":
            withTimeout("tell application \"Firefox\" to return URL of active tab of front window"),
        "com.microsoft.edgemac":
            withTimeout("tell application \"Microsoft Edge\" to return URL of active tab of front window"),
    ]

    private static func withTimeout(_ line: String) -> String {
        "with timeout of 2 seconds\n\(line)\nend timeout"
    }

    private static func browserURL(for app: NSRunningApplication) -> String? {
        guard let bundleId = app.bundleIdentifier,
              let script = browserScripts[bundleId] else { return nil }
        var error: NSDictionary?
        let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error == nil ? result?.stringValue : nil
    }
}
