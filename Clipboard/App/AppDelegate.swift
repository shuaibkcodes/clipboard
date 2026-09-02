import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsManager()
    private lazy var store = ClipboardStore(
        settings: settings,
        fileURL: isPreviewMode
            ? FileManager.default.temporaryDirectory.appendingPathComponent("ClipBoardPreview/history.json")
            : nil
    )
    private lazy var clipboardManager = ClipboardManager(store: store)
    private lazy var pasteManager = PasteManager(clipboardManager: clipboardManager)
    private let hotKeyManager = HotKeyManager()
    private lazy var panelController = ClipboardPanelController(
        store: store,
        settings: settings,
        pasteManager: pasteManager
    )

    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?

    private var isPreviewMode: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview") ||
            ProcessInfo.processInfo.arguments.contains("--render-preview")
        #else
        false
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        let isPreview = isPreviewMode
        NSApp.setActivationPolicy(isPreview ? .regular : .accessory)
        #else
        NSApp.setActivationPolicy(.accessory)
        #endif
        _ = store
        configureMenuBar()
        registerHotKey()
        settings.onShortcutChanged = { [weak self] in self?.registerHotKey() }
        clipboardManager.start()

        #if DEBUG
        if isPreview {
            store.clear(preservingPinned: false)
            ["development-api", "localhost:3000", "mongodb://localhost", "docker-compose", "docker run -d --name my-app -p 3000:3000"].forEach { store.add($0) }
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--render-preview"), arguments.indices.contains(flag + 1) {
                do {
                    try panelController.renderPreview(to: URL(fileURLWithPath: arguments[flag + 1]))
                } catch {
                    NSLog("ClipBoard preview rendering failed: %@", error.localizedDescription)
                }
                NSApp.terminate(nil)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.panelController.showForPreview()
                }
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardManager.stop()
        hotKeyManager.unregister()
    }

    private func registerHotKey() {
        hotKeyManager.register(shortcut: settings.shortcut) { [weak self] in
            self?.panelController.toggle()
        }
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "ClipBoard")

        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Clipboard History", action: #selector(openHistory), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let clear = NSMenuItem(title: "Clear Unpinned History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit ClipBoard", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    @objc private func openHistory() {
        panelController.show()
    }

    @objc private func clearHistory() {
        store.clear(preservingPinned: true)
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(
                settings: settings,
                hotKeyManager: hotKeyManager,
                store: store,
                pasteManager: pasteManager
            ))
            let window = NSWindow(contentViewController: controller)
            window.title = "ClipBoard Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
