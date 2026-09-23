import Foundation

/// UserDefaults-backed app settings.
final class PreferencesManager {
    static let shared = PreferencesManager()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let historyLimit = "historyLimit"
        static let autoDeleteDays = "autoDeleteDays"
        static let pollingInterval = "pollingInterval"
        static let maxTextBytes = "maxTextBytes"
        static let maxImageBytes = "maxImageBytes"
        static let ignoredBundleIDs = "ignoredBundleIDs"
        static let monitoringPaused = "monitoringPaused"
        static let hotkeyKeyCode = "hotkeyKeyCode"
        static let hotkeyModifiers = "hotkeyModifiers"
        static let encryptionEnabled = "encryptionEnabled"
    }

    private init() {
        defaults.register(defaults: [
            Key.historyLimit: 100,
            Key.autoDeleteDays: 30,
            Key.pollingInterval: 0.75,
            Key.maxTextBytes: 1_048_576,      // 1 MB
            Key.maxImageBytes: 10_485_760,    // 10 MB
            Key.ignoredBundleIDs: [String](),
            Key.monitoringPaused: false,
            Key.hotkeyKeyCode: Int(KeyboardShortcut.defaultShortcut.keyCode),
            Key.hotkeyModifiers: Int(KeyboardShortcut.defaultShortcut.carbonModifiers),
            Key.encryptionEnabled: false
        ])
    }

    var historyLimit: Int {
        get { max(1, defaults.integer(forKey: Key.historyLimit)) }
        set { defaults.set(newValue, forKey: Key.historyLimit) }
    }

    var autoDeleteDays: Int {
        get { max(1, defaults.integer(forKey: Key.autoDeleteDays)) }
        set { defaults.set(newValue, forKey: Key.autoDeleteDays) }
    }

    var pollingInterval: TimeInterval {
        get { min(max(defaults.double(forKey: Key.pollingInterval), 0.25), 5.0) }
        set { defaults.set(newValue, forKey: Key.pollingInterval) }
    }

    var maxTextBytes: Int {
        defaults.integer(forKey: Key.maxTextBytes)
    }

    var maxImageBytes: Int {
        defaults.integer(forKey: Key.maxImageBytes)
    }

    var userIgnoredBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.ignoredBundleIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.ignoredBundleIDs) }
    }

    var monitoringPaused: Bool {
        get { defaults.bool(forKey: Key.monitoringPaused) }
        set { defaults.set(newValue, forKey: Key.monitoringPaused) }
    }

    var panelShortcut: KeyboardShortcut {
        get {
            KeyboardShortcut(
                keyCode: UInt32(defaults.integer(forKey: Key.hotkeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Key.hotkeyModifiers))
            )
        }
        set {
            defaults.set(Int(newValue.keyCode), forKey: Key.hotkeyKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotkeyModifiers)
        }
    }

    var encryptionEnabled: Bool {
        get { defaults.bool(forKey: Key.encryptionEnabled) }
        set { defaults.set(newValue, forKey: Key.encryptionEnabled) }
    }
}
