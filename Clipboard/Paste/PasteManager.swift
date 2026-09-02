import AppKit
import ApplicationServices

@MainActor
final class PasteManager {
    private let pasteboard: NSPasteboard
    private weak var clipboardManager: ClipboardManager?

    init(clipboardManager: ClipboardManager, pasteboard: NSPasteboard = .general) {
        self.clipboardManager = clipboardManager
        self.pasteboard = pasteboard
    }

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    func paste(
        content: String,
        into previousApplication: NSRunningApplication?,
        automaticallyPaste: Bool,
        panelWillHide: () -> Void
    ) {
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)
        clipboardManager?.noteOwnWrite()
        panelWillHide()

        guard let previousApplication, !previousApplication.isTerminated else { return }

        previousApplication.activate(options: [.activateIgnoringOtherApps])

        guard automaticallyPaste, hasAccessibilityPermission else { return }

        // Activation restores the prior key window asynchronously. A single short delay
        // lets AppKit restore its first responder before the normal Command-V event.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.07) {
            guard !previousApplication.isTerminated else { return }
            let source = CGEventSource(stateID: .combinedSessionState)
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)
        }
    }

    func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
