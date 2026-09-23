import AppKit

/// Restores a stored history item back onto the general pasteboard,
/// including any preserved rich representations.
enum ClipboardWriter {
    static func write(item: ClipboardItem, formats: [ClipboardItemFormat], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        switch item.type {
        case .text, .url:
            if let text = item.plainText {
                pasteboard.setString(text, forType: .string)
            }
            if item.type == .url, let text = item.plainText, let url = URL(string: text) {
                (url as NSURL).write(to: pasteboard)
                // NSURL.write replaces contents; re-add the string form.
                pasteboard.setString(text, forType: .string)
            }
            for format in formats {
                let type = NSPasteboard.PasteboardType(format.pasteboardType)
                if let text = format.textValue {
                    pasteboard.setString(text, forType: type)
                } else if let data = FileStorage.loadData(atPath: format.dataPath) {
                    pasteboard.setData(data, forType: type)
                }
            }

        case .image:
            if let data = FileStorage.loadData(atPath: item.filePath) {
                pasteboard.setData(data, forType: .png)
                if let rep = NSBitmapImageRep(data: data),
                   let tiff = rep.tiffRepresentation {
                    pasteboard.setData(tiff, forType: .tiff)
                }
            }

        case .file:
            let urls = item.fileURLs.filter {
                FileManager.default.fileExists(atPath: $0.path)
            }
            if !urls.isEmpty {
                pasteboard.writeObjects(urls as [NSURL])
            } else if let text = item.plainText {
                // Files no longer exist; fall back to the paths as text.
                pasteboard.setString(text, forType: .string)
            }
        }
    }
}
