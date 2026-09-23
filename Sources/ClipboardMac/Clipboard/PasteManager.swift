import AppKit
import ApplicationServices

/// Restores a selected item to the pasteboard and pastes it into the app
/// that was active before the panel opened.
final class PasteManager {
    private let store: ClipboardStore
    private let monitor: ClipboardMonitor

    init(store: ClipboardStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
    }

    /// True when the app can synthesize keyboard events (Accessibility).
    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system prompt asking the user to grant Accessibility.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Puts the item on the pasteboard, refocuses the previous app, and
    /// simulates ⌘V. Without Accessibility permission the item is still
    /// copied so the user can paste manually.
    func paste(item: ClipboardItem, into previousApp: NSRunningApplication?) {
        let formats = (try? store.formats(for: item.id)) ?? []

        monitor.ignoreNextChange = true
        ClipboardWriter.write(item: item, formats: formats, to: NSPasteboard.general)

        previousApp?.activate(options: [])

        guard Self.hasAccessibilityPermission else {
            Self.requestAccessibilityPermission()
            return
        }

        // Give the previous app a moment to become key before sending ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.simulateCommandV()
        }
    }

    static func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let vKey: CGKeyCode = 0x09

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
