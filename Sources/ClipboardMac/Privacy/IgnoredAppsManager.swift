import Foundation

/// Apps whose copies are never recorded. Password managers are excluded
/// by default; users can add more bundle IDs in Preferences.
final class IgnoredAppsManager {
    static let shared = IgnoredAppsManager()

    static let defaultIgnoredBundleIDs: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess",
        "com.apple.Passwords"
    ]

    private init() {}

    var ignoredBundleIDs: Set<String> {
        Self.defaultIgnoredBundleIDs.union(PreferencesManager.shared.userIgnoredBundleIDs)
    }

    func isIgnored(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier = bundleIdentifier?.lowercased() else { return false }
        return ignoredBundleIDs.contains { $0.lowercased() == bundleIdentifier }
    }
}
