import AppKit

/// Owns the status bar item and its menu.
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let pauseMenuItem: NSMenuItem
    private let openMenuItem: NSMenuItem

    var onOpenHistory: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onClearHistory: (() -> Void)?
    var onExportHistory: (() -> Void)?
    var onImportHistory: (() -> Void)?
    var onOpenPreferences: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clipboard History"
        )

        let menu = NSMenu()

        openMenuItem = NSMenuItem(
            title: "Open Clipboard History",
            action: #selector(openHistory),
            keyEquivalent: ""
        )
        menu.addItem(openMenuItem)

        menu.addItem(.separator())

        pauseMenuItem = NSMenuItem(
            title: "Pause Monitoring",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        menu.addItem(pauseMenuItem)

        let clearItem = NSMenuItem(
            title: "Clear History…",
            action: #selector(clearHistory),
            keyEquivalent: ""
        )
        menu.addItem(clearItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Export History…",
            action: #selector(exportHistory),
            keyEquivalent: ""
        ))
        menu.addItem(NSMenuItem(
            title: "Import History…",
            action: #selector(importHistory),
            keyEquivalent: ""
        ))

        menu.addItem(.separator())

        let preferencesItem = NSMenuItem(
            title: "Preferences…",
            action: #selector(openPreferences),
            keyEquivalent: ","
        )
        menu.addItem(preferencesItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit ClipboardMac",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) {
            item.target = self
        }

        statusItem.menu = menu
        updateOpenShortcut(PreferencesManager.shared.panelShortcut)
    }

    /// Reflects the customizable global shortcut in the menu item.
    func updateOpenShortcut(_ shortcut: KeyboardShortcut) {
        openMenuItem.keyEquivalent = shortcut.keyEquivalent
        openMenuItem.keyEquivalentModifierMask = shortcut.nsModifiers
    }

    func setPaused(_ paused: Bool) {
        pauseMenuItem.title = paused ? "Resume Monitoring" : "Pause Monitoring"
        statusItem.button?.image = NSImage(
            systemSymbolName: paused ? "doc.on.clipboard" : "doc.on.clipboard.fill",
            accessibilityDescription: "Clipboard History"
        )
        statusItem.button?.appearsDisabled = paused
    }

    @objc private func openHistory() { onOpenHistory?() }
    @objc private func togglePause() { onTogglePause?() }
    @objc private func clearHistory() { onClearHistory?() }
    @objc private func exportHistory() { onExportHistory?() }
    @objc private func importHistory() { onImportHistory?() }
    @objc private func openPreferences() { onOpenPreferences?() }
}
