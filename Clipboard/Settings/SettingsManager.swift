import AppKit
import Carbon
import Foundation
import ServiceManagement

struct ShortcutChoice: Identifiable, Hashable {
    let id: String
    let title: String
    let keyCode: UInt32
    let modifiers: UInt32

    static let choices: [ShortcutChoice] = [
        .init(id: "option-v", title: "Option + V", keyCode: 9, modifiers: UInt32(optionKey)),
        .init(id: "command-shift-v", title: "Command + Shift + V", keyCode: 9, modifiers: UInt32(cmdKey | shiftKey)),
        .init(id: "control-option-v", title: "Control + Option + V", keyCode: 9, modifiers: UInt32(controlKey | optionKey))
    ]
}

@MainActor
final class SettingsManager: ObservableObject {
    private enum Key {
        static let historyLimit = "historyLimit"
        static let shortcutID = "shortcutID"
        static let automaticallyPaste = "automaticallyPaste"
    }

    private let defaults: UserDefaults
    var onHistoryLimitChanged: (() -> Void)?
    var onShortcutChanged: (() -> Void)?

    @Published var historyLimit: Int {
        didSet {
            historyLimit = min(1_000, max(10, historyLimit))
            defaults.set(historyLimit, forKey: Key.historyLimit)
            onHistoryLimitChanged?()
        }
    }

    @Published var shortcutID: String {
        didSet {
            defaults.set(shortcutID, forKey: Key.shortcutID)
            onShortcutChanged?()
        }
    }

    @Published var automaticallyPaste: Bool {
        didSet { defaults.set(automaticallyPaste, forKey: Key.automaticallyPaste) }
    }

    @Published private(set) var launchAtLogin: Bool = false
    @Published private(set) var launchAtLoginError: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.historyLimit: 100,
            Key.shortcutID: ShortcutChoice.choices[0].id,
            Key.automaticallyPaste: true
        ])
        historyLimit = defaults.integer(forKey: Key.historyLimit)
        shortcutID = defaults.string(forKey: Key.shortcutID) ?? ShortcutChoice.choices[0].id
        automaticallyPaste = defaults.bool(forKey: Key.automaticallyPaste)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var shortcut: ShortcutChoice {
        ShortcutChoice.choices.first(where: { $0.id == shortcutID }) ?? ShortcutChoice.choices[0]
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }
}
