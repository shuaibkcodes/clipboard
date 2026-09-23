import AppKit

/// Preferences window: startup, global shortcut, history limits, cleanup,
/// encryption, ignored apps, and Accessibility permission status.
final class PreferencesWindowController: NSWindowController {
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Start ClipboardMac at login", target: nil, action: nil)
    private let shortcutButton = ShortcutRecorderButton(frame: .zero)
    private let historyLimitField = NSTextField()
    private let autoDeleteField = NSTextField()
    private let encryptionCheckbox = NSButton(checkboxWithTitle: "Encrypt clipboard database", target: nil, action: nil)
    private let ignoredAppsView = NSTextView()
    private let accessibilityStatusLabel = NSTextField(labelWithString: "")

    /// Called when settings that affect the monitor/cleanup/hotkey change.
    var onSettingsChanged: (() -> Void)?
    /// Called when the encryption checkbox is toggled. Returns whether the
    /// migration succeeded; on failure the checkbox reverts.
    var onEncryptionToggled: ((Bool) -> Bool)?

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "ClipboardMac Preferences"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        loadValues()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func loadValues() {
        let prefs = PreferencesManager.shared
        launchAtLoginCheckbox.state = LoginItemManager.isEnabled ? .on : .off
        launchAtLoginCheckbox.isEnabled = LoginItemManager.isSupported
        shortcutButton.shortcut = prefs.panelShortcut
        historyLimitField.stringValue = String(prefs.historyLimit)
        autoDeleteField.stringValue = String(prefs.autoDeleteDays)
        encryptionCheckbox.state = prefs.encryptionEnabled ? .on : .off
        ignoredAppsView.string = prefs.userIgnoredBundleIDs.sorted().joined(separator: "\n")
        updateAccessibilityStatus()
    }

    private func saveValues() {
        let prefs = PreferencesManager.shared
        if let limit = Int(historyLimitField.stringValue), limit > 0 {
            prefs.historyLimit = limit
        }
        if let days = Int(autoDeleteField.stringValue), days > 0 {
            prefs.autoDeleteDays = days
        }
        let bundleIDs = ignoredAppsView.string
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        prefs.userIgnoredBundleIDs = Set(bundleIDs)
        onSettingsChanged?()
    }

    private func updateAccessibilityStatus() {
        if PasteManager.hasAccessibilityPermission {
            accessibilityStatusLabel.stringValue = "✓ Accessibility permission granted — auto-paste enabled"
            accessibilityStatusLabel.textColor = .systemGreen
        } else {
            accessibilityStatusLabel.stringValue = "✗ No Accessibility permission — items are copied, paste manually with ⌘V"
            accessibilityStatusLabel.textColor = .systemOrange
        }
    }

    // MARK: - Actions

    @objc private func toggleLaunchAtLogin() {
        let enabled = launchAtLoginCheckbox.state == .on
        do {
            try LoginItemManager.setEnabled(enabled)
        } catch {
            launchAtLoginCheckbox.state = enabled ? .off : .on
            presentError(
                title: "Could not update login item",
                message: "\(error)\n\nStart at login requires macOS 13+ and running ClipboardMac from the built .app bundle."
            )
        }
    }

    @objc private func toggleEncryption() {
        let enabled = encryptionCheckbox.state == .on
        let succeeded = onEncryptionToggled?(enabled) ?? false
        if !succeeded {
            encryptionCheckbox.state = enabled ? .off : .on
        }
    }

    @objc private func requestAccessibility() {
        PasteManager.requestAccessibilityPermission()
        // Status will refresh next time the window opens; also poll shortly.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.updateAccessibilityStatus()
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    // MARK: - UI construction

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 13)
            return field
        }

        func note(_ text: String) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: 11)
            field.textColor = .secondaryLabelColor
            return field
        }

        func fieldRow(_ title: String, field: NSTextField) -> NSStackView {
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 80).isActive = true
            let row = NSStackView(views: [label(title), NSView(), field])
            row.orientation = .horizontal
            return row
        }

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin)

        shortcutButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        shortcutButton.onShortcutChanged = { [weak self] shortcut in
            PreferencesManager.shared.panelShortcut = shortcut
            self?.onSettingsChanged?()
        }
        let shortcutRow = NSStackView(views: [label("Open panel shortcut:"), NSView(), shortcutButton])
        shortcutRow.orientation = .horizontal

        encryptionCheckbox.target = self
        encryptionCheckbox.action = #selector(toggleEncryption)

        let ignoredLabel = note("Ignored apps (one bundle ID per line, password managers are always ignored):")

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        ignoredAppsView.isRichText = false
        ignoredAppsView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        ignoredAppsView.autoresizingMask = [.width]
        scrollView.documentView = ignoredAppsView

        accessibilityStatusLabel.font = .systemFont(ofSize: 11)
        accessibilityStatusLabel.lineBreakMode = .byWordWrapping
        accessibilityStatusLabel.maximumNumberOfLines = 2
        accessibilityStatusLabel.preferredMaxLayoutWidth = 420

        let accessibilityButton = NSButton(
            title: "Request Accessibility Permission…",
            target: self,
            action: #selector(requestAccessibility)
        )
        accessibilityButton.bezelStyle = .rounded

        let stack = NSStackView(views: [
            launchAtLoginCheckbox,
            note("Requires macOS 13 or later."),
            shortcutRow,
            note("Click, then press the new shortcut. Esc cancels, ⌫ restores ⌥⌘V."),
            fieldRow("Maximum history items:", field: historyLimitField),
            fieldRow("Auto-delete after (days):", field: autoDeleteField),
            encryptionCheckbox,
            note("Encrypts history text and images on disk with a key stored in your Keychain. Toggling re-encodes existing items."),
            ignoredLabel,
            scrollView,
            accessibilityStatusLabel,
            accessibilityButton
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.setCustomSpacing(2, after: launchAtLoginCheckbox)
        stack.setCustomSpacing(2, after: shortcutRow)
        stack.setCustomSpacing(2, after: encryptionCheckbox)
        stack.setCustomSpacing(4, after: ignoredLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20)
        ])

        for row in stack.arrangedSubviews where row is NSStackView || row is NSScrollView {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
}

extension PreferencesWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        saveValues()
    }
}
