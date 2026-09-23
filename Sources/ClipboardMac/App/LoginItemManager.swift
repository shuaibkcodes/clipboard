import Foundation
import ServiceManagement

/// Registers the app as a login item via SMAppService (macOS 13+).
/// Requires running from a real .app bundle; registration from a bare
/// executable (e.g. `swift run`) fails with an error.
struct LoginItemError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

enum LoginItemManager {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) { return true }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LoginItemError(message: "Start at login requires macOS 13 or later")
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
