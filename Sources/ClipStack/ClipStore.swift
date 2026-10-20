import AppKit
import Foundation

/// Holds clipboard history, persists it to ~/Library/Application Support/ClipStack.
final class ClipStore {
    /// Posted (userInfo["item"]) whenever a new clip is captured.
    static let didAdd = Notification.Name("ClipStackDidAddItem")

    private(set) var items: [ClipItem] = [] {
        didSet { onChange?() }
    }
    /// Called on the main thread whenever history changes.
    var onChange: (() -> Void)?

    private let dir: URL
    private let dbURL: URL
    private let imagesDir: URL
    private var settingsObserver: NSObjectProtocol?

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("ClipStack", isDirectory: true)
        dbURL = dir.appendingPathComponent("history.json")
        imagesDir = dir.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        load()
        settingsObserver = NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.trim(); self?.save()
        }
    }

    // MARK: Mutations

    func addText(_ text: String, rtf: Data? = nil, html: String? = nil) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // De-duplicate: move an identical entry to the top instead of re-adding.
        if let idx = items.firstIndex(where: { $0.kind == .text && $0.text == text }) {
            var existing = items.remove(at: idx)
            // Upgrade a plain entry if the new copy carries formatting.
            if !existing.isRich && (rtf != nil || html != nil) {
                var upgraded = ClipItem(text: text, rtf: rtf, html: html)
                upgraded.pinned = existing.pinned
                existing = upgraded
            }
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(text: text, rtf: rtf, html: html), at: 0)
        }
        trim(); save(); announce(items[0])
    }

    func addImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        let path = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        do {
            try png.write(to: path)
            items.insert(ClipItem(imagePath: path.path), at: 0)
            trim(); save(); announce(items[0])
        } catch {
            NSLog("ClipStack: failed to save image: \(error)")
        }
    }

    func addFiles(_ urls: [URL]) {
        let paths = urls.map(\.path)
        guard !paths.isEmpty else { return }
        if let idx = items.firstIndex(where: { $0.kind == .files && $0.filePaths == paths }) {
            let existing = items.remove(at: idx)
            items.insert(existing, at: 0)
        } else {
            items.insert(ClipItem(filePaths: paths), at: 0)
        }
        trim(); save(); announce(items[0])
    }

    /// Records a screenshot file: stores a downscaled thumbnail, keeps a reference to the original.
    @discardableResult
    func addScreenshot(at url: URL, appName: String?) -> ClipItem? {
        guard let img = NSImage(contentsOf: url) else { return nil }
        let thumb = Self.downscale(img, maxSide: 1000)
        guard let tiff = thumb.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        let path = imagesDir.appendingPathComponent(UUID().uuidString + ".png")
        do { try png.write(to: path) } catch { return nil }
        var item = ClipItem(imagePath: path.path)
        item.sourcePath = url.path
        item.appName = appName
        items.insert(item, at: 0)
        trim(); save(); announce(items[0])
        return item
    }

    func setOCRText(_ text: String, for item: ClipItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].ocrText = text
        save()
    }

    /// Moves a screenshot's original file to the Trash and removes the entry.
    func trashScreenshot(_ item: ClipItem) {
        if let url = item.sourceURL { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }
        remove(item)
    }

    private static func downscale(_ img: NSImage, maxSide: CGFloat) -> NSImage {
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return img }
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        let scale = min(1, maxSide / max(w, h))
        guard scale < 1 else { return img }
        let size = NSSize(width: w * scale, height: h * scale)
        let out = NSImage(size: size)
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        img.draw(in: NSRect(origin: .zero, size: size))
        out.unlockFocus()
        return out
    }

    func togglePin(_ item: ClipItem) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx].pinned.toggle()
        save()
    }

    func remove(_ item: ClipItem) {
        items.removeAll { $0 == item }
        deleteFile(for: item)
        save()
    }

    func clear(keepPinned: Bool = true) {
        let removed = keepPinned ? items.filter { !$0.pinned } : items
        removed.forEach(deleteFile)
        items = keepPinned ? items.filter { $0.pinned } : []
        save()
    }

    // MARK: Queries

    enum Filter: Int, CaseIterable {
        case all, text, images, screenshots, files
        var title: String {
            switch self {
            case .all: return "All"; case .text: return "Text"; case .images: return "Images"
            case .screenshots: return "Screenshots"; case .files: return "Files"
            }
        }
        func matches(_ i: ClipItem) -> Bool {
            switch self {
            case .all: return true
            case .text: return i.kind == .text
            case .images: return i.kind == .image && !i.isScreenshot
            case .screenshots: return i.isScreenshot
            case .files: return i.kind == .files
            }
        }
    }

    func filtered(_ query: String, filter: Filter = .all) -> [ClipItem] {
        let sorted = items.filter(filter.matches).sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.createdAt > b.createdAt
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return sorted }
        return sorted.filter { item in
            item.searchText.localizedCaseInsensitiveContains(q)
                || (item.appName ?? "").localizedCaseInsensitiveContains(q)
                || item.smartType.rawValue.localizedCaseInsensitiveContains(q)
        }
    }

    private func announce(_ item: ClipItem) {
        NotificationCenter.default.post(name: Self.didAdd, object: self, userInfo: ["item": item])
    }

    // MARK: Persistence

    private func trim() {
        let unpinned = items.filter { !$0.pinned }
        let limit = Settings.maxItems
        if unpinned.count > limit {
            let overflow = unpinned.suffix(unpinned.count - limit)
            overflow.forEach(deleteFile)
            let ids = Set(overflow.map(\.id))
            items.removeAll { ids.contains($0.id) }
        }
    }

    private func deleteFile(for item: ClipItem) {
        if let p = item.imagePath { try? FileManager.default.removeItem(atPath: p) }
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(items)
            try data.write(to: dbURL, options: .atomic)
        } catch {
            NSLog("ClipStack: save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: dbURL),
              let decoded = try? JSONDecoder().decode([ClipItem].self, from: data) else { return }
        items = decoded
    }
}
