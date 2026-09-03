import AppKit
import SwiftUI

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private let panel: ClipboardPanel
    private let viewModel: PanelViewModel
    private let settings: SettingsManager
    private let pasteManager: PasteManager
    private var previousApplication: NSRunningApplication?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var keepsVisibleForPreview = false

    var isVisible: Bool { panel.isVisible }

    init(store: ClipboardStore, settings: SettingsManager, pasteManager: PasteManager) {
        self.settings = settings
        self.pasteManager = pasteManager
        viewModel = PanelViewModel(store: store)

        panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 480),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = NSHostingController(
            rootView: ClipboardPanelView(viewModel: viewModel, store: store)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        panel.setContentSize(NSSize(width: 400, height: 480))
        panel.minSize = NSSize(width: 400, height: 480)
        panel.maxSize = NSSize(width: 400, height: 480)

        viewModel.onClose = { [weak self] in self?.hide() }
        viewModel.onPaste = { [weak self] item in self?.select(item) }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self?.keepsVisibleForPreview != true else { return }
                self?.hide()
            }
        }
    }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        keepsVisibleForPreview = false
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }

        viewModel.reset()
        positionOnActiveScreen()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    #if DEBUG
    func showForPreview() {
        keepsVisibleForPreview = true
        viewModel.reset()
        positionOnActiveScreen()
        panel.orderFrontRegardless()
    }

    func renderPreview(to url: URL) throws {
        viewModel.reset()
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.setContentSize(NSSize(width: 400, height: 480))
        guard let contentView = panel.contentView else { throw CocoaError(.fileWriteUnknown) }
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()
        guard let bitmap = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        bitmap.size = contentView.bounds.size
        contentView.cacheDisplay(in: contentView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url, options: .atomic)
    }
    #endif

    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !keepsVisibleForPreview else { return }
        hide()
    }

    private func select(_ item: ClipboardItem) {
        pasteManager.paste(
            content: item.content,
            into: previousApplication,
            automaticallyPaste: settings.automaticallyPaste,
            panelWillHide: { [weak self] in self?.hide() }
        )
    }

    private func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = NSPoint(
            x: visible.midX - panel.frame.width / 2,
            y: visible.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.viewModel.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
