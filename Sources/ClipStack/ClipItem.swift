import AppKit
import Foundation

enum ClipKind: String, Codable {
    case text
    case image
    case files
}

struct ClipItem: Identifiable, Codable, Equatable {
    let id: UUID
    let kind: ClipKind
    let text: String?          // plain text (text items) — always present for .text
    let rtf: Data?             // optional rich text alongside plain text
    let html: String?          // optional HTML alongside plain text
    let imagePath: String?     // on-disk PNG path (image items)
    let filePaths: [String]?   // file URLs copied from Finder
    let createdAt: Date
    var pinned: Bool

    init(text: String, rtf: Data? = nil, html: String? = nil) {
        id = UUID(); kind = .text
        self.text = text; self.rtf = rtf; self.html = html
        imagePath = nil; filePaths = nil
        createdAt = Date(); pinned = false
    }

    init(imagePath: String) {
        id = UUID(); kind = .image
        text = nil; rtf = nil; html = nil
        self.imagePath = imagePath; filePaths = nil
        createdAt = Date(); pinned = false
    }

    init(filePaths: [String]) {
        id = UUID(); kind = .files
        text = filePaths.joined(separator: "\n"); rtf = nil; html = nil
        imagePath = nil; self.filePaths = filePaths
        createdAt = Date(); pinned = false
    }

    var isRich: Bool { rtf != nil || html != nil }

    var preview: String {
        switch kind {
        case .text:
            let t = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let firstLine = t.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? t
            return firstLine.count > 120 ? String(firstLine.prefix(120)) + "…" : firstLine
        case .image:
            if let img = image { return "Image \(Int(img.size.width))×\(Int(img.size.height))" }
            return "Image"
        case .files:
            let names = (filePaths ?? []).map { ($0 as NSString).lastPathComponent }
            return names.count == 1 ? names[0] : "\(names.count) files: " + names.joined(separator: ", ")
        }
    }

    var image: NSImage? {
        guard let p = imagePath else { return nil }
        return NSImage(contentsOfFile: p)
    }

    var fileURLs: [URL] { (filePaths ?? []).map { URL(fileURLWithPath: $0) } }

    /// Lazily detected content type (URL, email, JSON…). Only meaningful for text items.
    var smartType: SmartType { SmartType.detect(self) }

    static func == (a: ClipItem, b: ClipItem) -> Bool { a.id == b.id }
}
