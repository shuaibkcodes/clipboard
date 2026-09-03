import AppKit

@MainActor
final class ClipboardManager {
    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipboardStore, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPasteboard() }
        }
        timer?.tolerance = 0.15
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func noteOwnWrite() {
        lastChangeCount = pasteboard.changeCount
    }

    func checkPasteboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        // Respect common conventions used for transient and concealed clipboard values.
        if pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.TransientType")) == true ||
            pasteboard.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true {
            return
        }
        guard let text = pasteboard.string(forType: .string) else { return }
        store.add(text)
    }
}
