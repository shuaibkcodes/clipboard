import AppKit

/// Panel that can become key even though it's a borderless-style utility.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Table view that owns keyboard focus when the panel opens: arrows and
/// Page Up/Down/Home/End navigate natively, Return pastes, Esc closes,
/// and typing any printable character redirects to the search field.
final class HistoryTableView: NSTableView {
    var onPaste: (() -> Void)?
    var onClose: (() -> Void)?
    var onTypeToSearch: ((String) -> Void)?

    /// The very first click must select/paste, not be swallowed by
    /// window activation.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var needsPanelToBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: // Return, keypad Enter
            onPaste?()
            return
        case 53: // Esc
            onClose?()
            return
        default:
            break
        }

        if isPrintable(event), let characters = event.characters {
            onTypeToSearch?(characters)
            return
        }

        super.keyDown(with: event)
    }

    private func isPrintable(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Allow ⇧/⌥ (capitals, accented chars); ⌘/⌃ are commands, not text.
        guard modifiers.subtracting([.shift, .option]).isEmpty else { return false }
        guard let characters = event.characters, !characters.isEmpty else { return false }
        for scalar in characters.unicodeScalars {
            // Control chars, delete, and NSEvent function-key range.
            if scalar.value < 0x20 || scalar.value == 0x7F || (0xF700...0xF8FF).contains(scalar.value) {
                return false
            }
        }
        return true
    }
}

/// The floating clipboard history window: search bar, item list,
/// preview area, and footer hints.
final class ClipboardPanelController: NSWindowController {
    private let searchField = NSSearchField()
    private let tableView = HistoryTableView()
    private let scrollView = NSScrollView()
    private let previewImageView = NSImageView()
    private let previewTextLabel = NSTextField(wrappingLabelWithString: "")
    private let emptyLabel = NSTextField(labelWithString: "No clipboard history yet")
    private let footerLabel = NSTextField(labelWithString: "↩ / Click Paste    ⌘P Pin    ⌘T Tag    ⌘⌫ Delete    Esc Close    Type to Search")

    private var items: [ClipboardItem] = []
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var isPresentingDialog = false

    /// Data source: given a search query, return matching items.
    var fetchItems: ((String?) -> [ClipboardItem])?
    var onPaste: ((ClipboardItem, NSRunningApplication?) -> Void)?
    var onTogglePin: ((ClipboardItem) -> Void)?
    var onDelete: ((ClipboardItem) -> Void)?
    var onSetTags: ((ClipboardItem, [String]) -> Void)?

    init() {
        // .nonactivatingPanel: the panel takes keyboard focus WITHOUT
        // activating this app. The previous app stays active, so the panel
        // gets key events immediately (no first-keystroke/first-click being
        // eaten by activation) and paste-back lands in the right app.
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard History"
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        super.init(window: panel)
        panel.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Show / hide

    func toggle() {
        if window?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        // Remember the app to paste back into before we steal focus.
        previousApp = NSWorkspace.shared.frontmostApplication

        searchField.stringValue = ""
        // Always open with the first (most recent or pinned) item selected.
        tableView.deselectAll(nil)
        reload(query: nil)

        window?.center()
        // Do NOT call NSApp.activate here: the nonactivating panel becomes
        // key on its own, and app activation from a hotkey callback is
        // unreliable on macOS 14+ (which caused lost first keystrokes).
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()

        // Focus the list so arrows/Page keys navigate immediately;
        // typing any character jumps to the search field. Re-assert async
        // in case AppKit moves focus while the panel becomes key.
        window?.makeFirstResponder(tableView)
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.window?.isVisible == true else { return }
            if self.window?.firstResponder !== self.tableView {
                self.window?.makeFirstResponder(self.tableView)
            }
        }

        installKeyMonitor()
    }

    override func close() {
        removeKeyMonitor()
        super.close()
    }

    /// Refresh contents if the panel is open (new copy arrived).
    func refreshIfVisible() {
        guard window?.isVisible == true else { return }
        reload(query: currentQuery)
    }

    private var currentQuery: String? {
        let text = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private func reload(query: String?) {
        let selectedID = selectedItem?.id
        items = fetchItems?(query) ?? []
        tableView.reloadData()
        emptyLabel.isHidden = !items.isEmpty

        if items.isEmpty {
            updatePreview(nil)
        } else {
            let row = items.firstIndex { $0.id == selectedID } ?? 0
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        }
    }

    private var selectedItem: ClipboardItem? {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return nil }
        return items[row]
    }

    // MARK: - Actions

    private func pasteSelected() {
        guard let item = selectedItem else { return }
        let target = previousApp
        close()
        onPaste?(item, target)
    }

    private func togglePinSelected() {
        guard let item = selectedItem else { return }
        onTogglePin?(item)
        reload(query: currentQuery)
    }

    private func deleteSelected() {
        guard let item = selectedItem else { return }
        let row = tableView.selectedRow
        onDelete?(item)
        reload(query: currentQuery)
        if !items.isEmpty {
            let newRow = min(row, items.count - 1)
            tableView.selectRowIndexes(IndexSet(integer: newRow), byExtendingSelection: false)
        }
    }

    /// ⌘T: edit comma-separated tags for the selected item in a small
    /// dialog. The dialog steals key status, so close-on-resign is
    /// suppressed while it is up.
    private func editTagsForSelected() {
        guard let item = selectedItem else { return }
        isPresentingDialog = true
        defer { isPresentingDialog = false }

        let alert = NSAlert()
        alert.messageText = "Edit Tags"
        alert.informativeText = "Comma-separated tags. Search them by typing #tag."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = item.tags.joined(separator: ", ")
        field.placeholderString = "work, snippets"
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let tags = field.stringValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            onSetTags?(item, tags)
            reload(query: currentQuery)
        }

        // Take focus back from the dismissed dialog.
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(tableView)
    }

    private func moveSelection(by delta: Int) {
        guard !items.isEmpty else { return }
        let current = max(tableView.selectedRow, 0)
        let next = min(max(current + delta, 0), items.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: - Key handling (⌘P, ⌘⌫ while panel is key)

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.window?.isKeyWindow == true else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if flags == .command {
                switch event.charactersIgnoringModifiers {
                case "p":
                    self.togglePinSelected()
                    return nil
                case "t":
                    self.editTagsForSelected()
                    return nil
                case "\u{7f}", "\u{08}": // ⌘⌫
                    self.deleteSelected()
                    return nil
                default:
                    break
                }
            }

            // Navigation works regardless of which control has focus.
            // (Arrow keys carry .function/.numericPad flags on macOS.)
            if flags.subtracting([.function, .numericPad]).isEmpty {
                switch event.keyCode {
                case 125: // ↓
                    self.moveSelection(by: 1)
                    return nil
                case 126: // ↑
                    self.moveSelection(by: -1)
                    return nil
                case 36, 76: // Return, keypad Enter
                    self.pasteSelected()
                    return nil
                case 53: // Esc
                    self.close()
                    return nil
                default:
                    break
                }
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search clipboard history"
        searchField.delegate = self

        tableView.headerView = nil
        tableView.rowHeight = ClipboardItemRow.rowHeight
        tableView.style = .inset
        tableView.allowsEmptySelection = true
        tableView.dataSource = self
        tableView.delegate = self
        // Single click pastes (pin/delete buttons consume their own clicks).
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.onPaste = { [weak self] in self?.pasteSelected() }
        tableView.onClose = { [weak self] in self?.close() }
        tableView.onTypeToSearch = { [weak self] characters in
            self?.redirectTypingToSearch(characters)
        }

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("item"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = .systemFont(ofSize: 13)

        let previewBox = NSBox()
        previewBox.translatesAutoresizingMaskIntoConstraints = false
        previewBox.boxType = .custom
        previewBox.borderColor = .separatorColor
        previewBox.borderWidth = 1
        previewBox.cornerRadius = 6
        previewBox.fillColor = .textBackgroundColor

        previewTextLabel.translatesAutoresizingMaskIntoConstraints = false
        previewTextLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        previewTextLabel.textColor = .labelColor
        previewTextLabel.cell?.truncatesLastVisibleLine = true
        previewTextLabel.maximumNumberOfLines = 5

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.imageScaling = .scaleProportionallyDown
        previewImageView.isHidden = true

        previewBox.contentView?.addSubview(previewTextLabel)
        previewBox.contentView?.addSubview(previewImageView)

        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .tertiaryLabelColor
        footerLabel.alignment = .center

        contentView.addSubview(searchField)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(previewBox)
        contentView.addSubview(footerLabel)

        guard let previewContent = previewBox.contentView else { return }

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 34),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: previewBox.topAnchor, constant: -8),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            previewBox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            previewBox.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            previewBox.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -6),
            previewBox.heightAnchor.constraint(equalToConstant: 96),

            previewTextLabel.topAnchor.constraint(equalTo: previewContent.topAnchor, constant: 8),
            previewTextLabel.leadingAnchor.constraint(equalTo: previewContent.leadingAnchor, constant: 8),
            previewTextLabel.trailingAnchor.constraint(equalTo: previewContent.trailingAnchor, constant: -8),
            previewTextLabel.bottomAnchor.constraint(lessThanOrEqualTo: previewContent.bottomAnchor, constant: -8),

            previewImageView.topAnchor.constraint(equalTo: previewContent.topAnchor, constant: 4),
            previewImageView.leadingAnchor.constraint(equalTo: previewContent.leadingAnchor, constant: 4),
            previewImageView.trailingAnchor.constraint(equalTo: previewContent.trailingAnchor, constant: -4),
            previewImageView.bottomAnchor.constraint(equalTo: previewContent.bottomAnchor, constant: -4),

            footerLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            footerLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            footerLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])
    }

    private func updatePreview(_ item: ClipboardItem?) {
        guard let item = item else {
            previewTextLabel.stringValue = ""
            previewImageView.image = nil
            previewImageView.isHidden = true
            previewTextLabel.isHidden = false
            return
        }

        if item.type == .image,
           let data = FileStorage.loadData(atPath: item.filePath),
           let image = NSImage(data: data) {
            previewImageView.image = image
            previewImageView.isHidden = false
            previewTextLabel.isHidden = true
        } else {
            let text = item.plainText ?? item.preview
            previewTextLabel.stringValue = String(text.prefix(1_000))
            previewImageView.isHidden = true
            previewTextLabel.isHidden = false
        }
    }

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        pasteSelected()
    }

    /// Typing while the list has focus moves focus to the search field
    /// and appends the typed characters, so search "just works".
    private func redirectTypingToSearch(_ characters: String) {
        window?.makeFirstResponder(searchField)
        if let editor = searchField.currentEditor() {
            let length = (editor.string as NSString).length
            editor.replaceCharacters(in: NSRange(location: length, length: 0), with: characters)
            let newLength = (editor.string as NSString).length
            editor.selectedRange = NSRange(location: newLength, length: 0)
        } else {
            searchField.stringValue += characters
        }
        reload(query: currentQuery)
    }
}

// MARK: - Table view

extension ClipboardPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: ClipboardItemRow.reuseIdentifier, owner: self)
            as? ClipboardItemRow ?? ClipboardItemRow(frame: .zero)

        cell.configure(with: items[row])
        cell.onTogglePin = { [weak self] item in
            self?.onTogglePin?(item)
            self?.reload(query: self?.currentQuery)
        }
        cell.onDelete = { [weak self] item in
            self?.onDelete?(item)
            self?.reload(query: self?.currentQuery)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updatePreview(selectedItem)
    }
}

// MARK: - Search field

extension ClipboardPanelController: NSSearchFieldDelegate {
    func controlTextDidChange(_ notification: Notification) {
        reload(query: currentQuery)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            pasteSelected()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }
}

// MARK: - Window delegate

extension ClipboardPanelController: NSWindowDelegate {
    func windowDidResignKey(_ notification: Notification) {
        // Dismiss when the user clicks elsewhere, like Spotlight — but not
        // when one of our own dialogs (tag editor) takes key status.
        guard !isPresentingDialog else { return }
        close()
    }
}
