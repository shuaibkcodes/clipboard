import AppKit

/// Button that records a keyboard shortcut: click it, press the new
/// combination. Esc cancels, Delete restores the default shortcut.
final class ShortcutRecorderButton: NSButton {
    var shortcut: KeyboardShortcut = PreferencesManager.shared.panelShortcut {
        didSet { refreshTitle() }
    }
    var onShortcutChanged: ((KeyboardShortcut) -> Void)?

    private var isRecording = false
    private var keyMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        stopRecording()
    }

    @objc private func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startRecording() {
        isRecording = true
        refreshTitle()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isRecording else { return event }

            switch event.keyCode {
            case 53: // Esc cancels
                self.stopRecording()
                return nil
            case 51: // Delete restores the default
                self.commit(.defaultShortcut)
                return nil
            default:
                break
            }

            if let recorded = KeyboardShortcut(event: event) {
                self.commit(recorded)
                return nil
            }

            // Ignore keystrokes without a usable modifier (⌘/⌥/⌃).
            NSSound.beep()
            return nil
        }
    }

    private func commit(_ newShortcut: KeyboardShortcut) {
        stopRecording()
        shortcut = newShortcut
        onShortcutChanged?(newShortcut)
    }

    private func stopRecording() {
        isRecording = false
        if let keyMonitor = keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        refreshTitle()
    }

    private func refreshTitle() {
        title = isRecording ? "Type shortcut… (Esc to cancel)" : shortcut.displayString
    }
}
