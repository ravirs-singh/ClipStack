import AppKit
import ImageIO
import Vision

/// Watches for new screenshots via Spotlight (kMDItemIsScreenCapture), optionally organizes them
/// into dated folders, runs OCR, and feeds them into the clip history.
final class ScreenshotWatcher {
    private let store: ClipStore
    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var seen = Set<String>()
    private var started = false
    private var dirSource: DispatchSourceFileSystemObject?
    private var dirFD: Int32 = -1
    private var knownFiles = Set<String>()
    private let ocrQueue = DispatchQueue(label: "ClipStack.ocr", qos: .utility)

    init(store: ClipStore) {
        self.store = store
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        query.sortDescriptors = [NSSortDescriptor(key: NSMetadataItemFSCreationDateKey, ascending: false)]

        observers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            self?.initialGather()
        })
        observers.append(NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] n in
            self?.didUpdate(n)
        })
        observers.append(NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.applyEnabled()
        })
        applyEnabled()
    }

    private func applyEnabled() {
        if Settings.screenshotsEnabled, !started {
            started = query.start()
            watchFolder()
        } else if !Settings.screenshotsEnabled, started {
            query.stop(); started = false
            stopWatchingFolder()
        }
    }

    // MARK: Folder watcher (primary — Spotlight indexing can lag or never fire)

    /// Where macOS saves screenshots: `defaults read com.apple.screencapture location`, else ~/Desktop.
    static var captureFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let p = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !p.isEmpty {
            let expanded = (p as NSString).expandingTildeInPath
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue { return URL(fileURLWithPath: expanded) }
        }
        return home.appendingPathComponent("Desktop")
    }

    private func watchFolder() {
        stopWatchingFolder()
        let folder = Self.captureFolder
        knownFiles = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        dirFD = open(folder.path, O_EVTONLY)
        guard dirFD >= 0 else { NSLog("ClipStack: cannot watch \(folder.path)"); return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: dirFD, eventMask: [.write, .rename], queue: .main)
        src.setEventHandler { [weak self] in self?.folderChanged(folder) }
        src.setCancelHandler { [fd = dirFD] in close(fd) }
        src.resume()
        dirSource = src
        NSLog("ClipStack: watching screenshots in \(folder.path)")
    }

    private func stopWatchingFolder() {
        dirSource?.cancel(); dirSource = nil; dirFD = -1
    }

    private func folderChanged(_ folder: URL) {
        guard let now = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
        let added = Set(now).subtracting(knownFiles)
        knownFiles = Set(now)
        for name in added where !name.hasPrefix(".") {
            let ext = (name as NSString).pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "heic", "tiff", "gif", "pdf"].contains(ext) else { continue }
            let url = folder.appendingPathComponent(name)
            // Only files created in the last few seconds — ignore things being moved in from elsewhere.
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let created = attrs[.creationDate] as? Date, Date().timeIntervalSince(created) > 10 { continue }
            guard !seen.contains(url.path) else { continue }
            seen.insert(url.path)
            ingest(url)
        }
    }

    /// Existing screenshots are remembered so only *new* ones get captured.
    private func initialGather() {
        query.disableUpdates()
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem,
               let p = item.value(forAttribute: NSMetadataItemPathKey) as? String { seen.insert(p) }
        }
        query.enableUpdates()
    }

    private func didUpdate(_ n: Notification) {
        guard let added = n.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] else { return }
        for item in added {
            guard let p = item.value(forAttribute: NSMetadataItemPathKey) as? String,
                  !seen.contains(p),
                  !(p as NSString).lastPathComponent.hasPrefix(".") else { continue }
            seen.insert(p)
            // Spotlight can fire while the file is still being finalized.
            ingest(URL(fileURLWithPath: p))
        }
    }

    // MARK: Ingest

    private let workQueue = DispatchQueue(label: "ClipStack.screenshots", qos: .userInitiated)

    private func ingest(_ original: URL) {
        let app = frontmostAppName()          // read on main, while the capturing app is still frontmost
        let organize = Settings.screenshotOrganize
        let ocr = Settings.screenshotOCR
        let thumbDir = store.imagesDir
        workQueue.async { [weak self] in
            guard let self, Self.waitUntilStable(original) else { return }
            var url = original
            if organize, let moved = self.organize(url, appName: app) { url = moved }
            guard let thumbPath = Self.makeThumbnail(of: url, maxPixel: 1000, into: thumbDir) else { return }
            DispatchQueue.main.async {
                if url != original { self.seen.insert(url.path) }
                let item = self.store.addScreenshot(source: url, thumbPath: thumbPath, appName: app)
                if ocr { self.runOCR(for: item, url: url) }
            }
        }
    }

    /// The screenshot file appears before it's fully written; poll until its size stops changing.
    private static func waitUntilStable(_ url: URL, timeout: TimeInterval = 3) -> Bool {
        let fm = FileManager.default
        var last: UInt64 = 0
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            guard fm.fileExists(atPath: url.path) else { usleep(50_000); continue }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            if size > 0 && size == last { return true }
            last = size
            usleep(80_000)
        }
        return fm.fileExists(atPath: url.path)
    }

    /// Fast downscale with ImageIO (no full decode on the main thread). Returns the written PNG path.
    private static func makeThumbnail(of url: URL, maxPixel: Int, into dir: URL) -> String? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = dir.appendingPathComponent(UUID().uuidString + ".png")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, nil)
        return CGImageDestinationFinalize(dest) ? out.path : nil
    }

    func frontmostAppName() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return app.localizedName
    }

    /// Moves into <folder>/YYYY-MM/"YYYY-MM-DD HH.MM.SS – App.ext". Returns the new URL, or nil if left in place.
    private func organize(_ url: URL, appName: String?) -> URL? {
        let fm = FileManager.default
        let base = Settings.screenshotFolder
        let now = Date()
        let month = DateFormatter(); month.dateFormat = "yyyy-MM"
        let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let dir = base.appendingPathComponent(month.string(from: now), isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { return nil }

        var name = stamp.string(from: now)
        if let appName, !appName.isEmpty { name += " – " + appName.replacingOccurrences(of: "/", with: "-") }
        var dest = dir.appendingPathComponent(name).appendingPathExtension(url.pathExtension)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(name) \(n)").appendingPathExtension(url.pathExtension); n += 1
        }
        do { try fm.moveItem(at: url, to: dest); return dest } catch {
            NSLog("ClipStack: could not organize screenshot: \(error)"); return nil
        }
    }

    // MARK: OCR

    private func runOCR(for item: ClipItem, url: URL) {
        ocrQueue.async { [weak self] in
            guard let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            let req = VNRecognizeTextRequest()
            req.recognitionLevel = .accurate
            req.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            guard (try? handler.perform([req])) != nil else { return }
            let lines = (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n")
            guard !text.isEmpty else { return }
            DispatchQueue.main.async { self?.store.setOCRText(text, for: item) }
        }
    }

    // MARK: Direct capture support

    /// Where ClipStack's own capture should write, honoring the organize setting.
    func plannedDestination(appName: String?) -> URL {
        let now = Date()
        if Settings.screenshotOrganize {
            let month = DateFormatter(); month.dateFormat = "yyyy-MM"
            let stamp = DateFormatter(); stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
            let dir = Settings.screenshotFolder.appendingPathComponent(month.string(from: now), isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var name = stamp.string(from: now)
            if let appName, !appName.isEmpty { name += " – " + appName.replacingOccurrences(of: "/", with: "-") }
            return dir.appendingPathComponent(name).appendingPathExtension("png")
        }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' h.mm.ss a"
        return Self.captureFolder.appendingPathComponent("Screenshot \(f.string(from: now)).png")
    }

    /// Mark a path as ours so the folder/Spotlight watchers don't ingest it a second time.
    func reserve(_ url: URL) { seen.insert(url.path); knownFiles.insert(url.lastPathComponent) }

    /// Ingest a file we wrote ourselves (already in its final place).
    func ingestNow(_ url: URL, appName: String?) {
        let ocr = Settings.screenshotOCR
        let thumbDir = store.imagesDir
        workQueue.async { [weak self] in
            guard let self, let thumbPath = Self.makeThumbnail(of: url, maxPixel: 1000, into: thumbDir) else { return }
            DispatchQueue.main.async {
                let item = self.store.addScreenshot(source: url, thumbPath: thumbPath, appName: appName)
                if ocr { self.runOCR(for: item, url: url) }
            }
        }
    }

    /// One-off OCR for an existing item (e.g. imported before OCR was enabled).
    func ocrNow(_ item: ClipItem) {
        guard let p = item.sourcePath ?? item.imagePath else { return }
        runOCR(for: item, url: URL(fileURLWithPath: p))
    }
}
