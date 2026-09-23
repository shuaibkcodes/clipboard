import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fileStorage: FileStorage!
    private var store: ClipboardStore!
    private var monitor: ClipboardMonitor!
    private var pasteManager: PasteManager!
    private var hotkeyManager: HotkeyManager!
    private var menuBarController: MenuBarController!
    private var panelController: ClipboardPanelController!
    private var preferencesController: PreferencesWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            fileStorage = try FileStorage()
            let database = try Database(path: fileStorage.databasePath)
            store = try ClipboardStore(database: database, fileStorage: fileStorage)
        } catch {
            presentFatalError(error)
            return
        }

        monitor = ClipboardMonitor()
        pasteManager = PasteManager(store: store, monitor: monitor)
        panelController = ClipboardPanelController()
        preferencesController = PreferencesWindowController()
        menuBarController = MenuBarController()
        hotkeyManager = HotkeyManager()

        wireComponents()

        monitor.isPaused = PreferencesManager.shared.monitoringPaused
        menuBarController.setPaused(monitor.isPaused)
        monitor.start(interval: PreferencesManager.shared.pollingInterval)
        hotkeyManager.register()

        runCleanup()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotkeyManager?.unregister()
    }

    // MARK: - Wiring

    private func wireComponents() {
        monitor.onCapture = { [weak self] captured, sourceAppName, _ in
            guard let self = self else { return }
            do {
                try self.store.save(captured, sourceApp: sourceAppName)
                self.runCleanup()
                self.panelController.refreshIfVisible()
            } catch {
                NSLog("ClipboardMac: failed to save item: \(error)")
            }
        }

        panelController.fetchItems = { [weak self] query in
            (try? self?.store.items(matching: query, limit: 200)) ?? []
        }
        panelController.onPaste = { [weak self] item, previousApp in
            self?.pasteManager.paste(item: item, into: previousApp)
        }
        panelController.onTogglePin = { [weak self] item in
            try? self?.store.setPinned(!item.isPinned, id: item.id)
        }
        panelController.onDelete = { [weak self] item in
            try? self?.store.delete(id: item.id)
        }
        panelController.onSetTags = { [weak self] item, tags in
            try? self?.store.setTags(tags, id: item.id)
        }

        menuBarController.onOpenHistory = { [weak self] in
            self?.panelController.toggle()
        }
        menuBarController.onTogglePause = { [weak self] in
            guard let self = self else { return }
            self.monitor.isPaused.toggle()
            PreferencesManager.shared.monitoringPaused = self.monitor.isPaused
            self.menuBarController.setPaused(self.monitor.isPaused)
        }
        menuBarController.onClearHistory = { [weak self] in
            self?.confirmClearHistory()
        }
        menuBarController.onExportHistory = { [weak self] in
            self?.exportHistory()
        }
        menuBarController.onImportHistory = { [weak self] in
            self?.importHistory()
        }
        menuBarController.onOpenPreferences = { [weak self] in
            self?.preferencesController.show()
        }

        preferencesController.onSettingsChanged = { [weak self] in
            guard let self = self else { return }
            self.monitor.start(interval: PreferencesManager.shared.pollingInterval)
            self.hotkeyManager.register()
            self.menuBarController.updateOpenShortcut(PreferencesManager.shared.panelShortcut)
            self.runCleanup()
        }
        preferencesController.onEncryptionToggled = { [weak self] enabled in
            guard let self = self else { return false }
            do {
                try self.store.applyEncryptionSetting(enabled)
                return true
            } catch {
                self.presentAlert(
                    title: "Could not change encryption",
                    message: String(describing: error),
                    style: .warning
                )
                return false
            }
        }

        hotkeyManager.onHotkey = { [weak self] in
            self?.panelController.toggle()
        }
    }

    // MARK: - Actions

    private func runCleanup() {
        let prefs = PreferencesManager.shared
        do {
            try store.cleanup(historyLimit: prefs.historyLimit, maxAgeDays: prefs.autoDeleteDays)
        } catch {
            NSLog("ClipboardMac: cleanup failed: \(error)")
        }
    }

    private func confirmClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All unpinned items will be deleted. Pinned items are kept."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            try? store.clearHistory(keepPinned: true)
            panelController.refreshIfVisible()
        }
    }

    // MARK: - Export / import

    private func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ClipboardMac-Export.json"
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.json]
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try store.exportJSON().write(to: url, options: .atomic)
            presentAlert(
                title: "Export complete",
                message: "Clipboard history was exported to \(url.lastPathComponent). The file is unencrypted JSON — treat it as sensitive.",
                style: .informational
            )
        } catch {
            presentAlert(title: "Export failed", message: String(describing: error), style: .warning)
        }
    }

    private func importHistory() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if #available(macOS 11.0, *) {
            panel.allowedContentTypes = [.json]
        }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let result = try store.importJSON(data)
            runCleanup()
            panelController.refreshIfVisible()
            presentAlert(
                title: "Import complete",
                message: "Imported \(result.imported) item(s); skipped \(result.skipped) duplicate(s).",
                style: .informational
            )
        } catch {
            presentAlert(title: "Import failed", message: String(describing: error), style: .warning)
        }
    }

    private func presentAlert(title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func presentFatalError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "ClipboardMac could not start"
        alert.informativeText = String(describing: error)
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
