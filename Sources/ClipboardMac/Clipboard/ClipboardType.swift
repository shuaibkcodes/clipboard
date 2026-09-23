import Foundation

enum ClipboardType: String {
    case text
    case url
    case image
    case file

    var symbolName: String {
        switch self {
        case .text: return "doc.text"
        case .url: return "link"
        case .image: return "photo"
        case .file: return "folder"
        }
    }

    var displayName: String {
        switch self {
        case .text: return "Text"
        case .url: return "URL"
        case .image: return "Image"
        case .file: return "File"
        }
    }
}
