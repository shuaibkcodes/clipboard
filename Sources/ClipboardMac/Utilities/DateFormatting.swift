import Foundation

enum DateFormatting {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    /// "Copied 2 minutes ago" style string.
    static func relative(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 10 {
            return "Copied just now"
        }
        return "Copied " + relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
