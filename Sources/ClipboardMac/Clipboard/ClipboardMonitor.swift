import AppKit

/// Polls NSPasteboard.general.changeCount and reports new clipboard content.
/// macOS has no clipboard-changed notification, so polling is the standard
/// approach (this is what every clipboard manager on macOS does).
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?

    /// Set true while the app itself writes to the pasteboard (paste-back)
    /// so we don't re-record our own writes.
    var ignoreNextChange = false

    var isPaused = false {
        didSet { lastChangeCount = pasteboard.changeCount }
    }

    /// Called on the main thread with new clipboard content and source app.
    var onCapture: ((CapturedClipboard, _ sourceAppName: String?, _ sourceBundleID: String?) -> Void)?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start(interval: TimeInterval) {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
        // .common mode keeps polling alive while menus/panels are open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount

        guard !isPaused else { return }

        if ignoreNextChange {
            ignoreNextChange = false
            return
        }

        let frontmost = NSWorkspace.shared.frontmostApplication
        let bundleID = frontmost?.bundleIdentifier

        // Skip apps the user excluded (password managers by default).
        if IgnoredAppsManager.shared.isIgnored(bundleIdentifier: bundleID) {
            return
        }

        guard let captured = ClipboardReader.read(from: pasteboard) else { return }

        // Never store content that looks like a secret.
        if let text = captured.plainText,
           SensitiveDataDetector.looksSensitive(text) {
            return
        }

        onCapture?(captured, frontmost?.localizedName, bundleID)
    }
}
