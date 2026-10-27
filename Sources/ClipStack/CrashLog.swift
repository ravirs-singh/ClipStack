import AppKit
import Darwin

/// Sends stderr (Swift fatal errors, NSLog) to ~/Library/Application Support/ClipStack/ClipStack.log and
/// records a backtrace on crash signals, so problems can be read from the file instead of a debugger.
enum CrashLog {
    static let path: String = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipStack", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("ClipStack.log").path
    }()

    static func install() {
        // Keep the log from growing forever.
        if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int, size > 2_000_000 {
            try? FileManager.default.removeItem(atPath: path)
        }
        freopen(path, "a", stderr)
        setvbuf(stderr, nil, _IONBF, 0)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fputs("\n===== ClipStack launched \(f.string(from: Date())) =====\n", stderr)

        NSSetUncaughtExceptionHandler { e in
            fputs("UNCAUGHT EXCEPTION: \(e.name.rawValue): \(e.reason ?? "")\n" + e.callStackSymbols.joined(separator: "\n") + "\n", stderr)
        }
        for sig in [SIGABRT, SIGTRAP, SIGILL, SIGSEGV, SIGBUS, SIGFPE] {
            signal(sig) { s in
                fputs("CRASH signal \(s)\n" + Thread.callStackSymbols.joined(separator: "\n") + "\n", stderr)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }
}
