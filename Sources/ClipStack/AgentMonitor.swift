import AppKit
import Network

/// Tracks AI coding agents (Claude Code today) through their hook system.
///
/// A tiny local HTTP server receives hook payloads. `Notification`/`Stop`/`PostToolUse` hooks post status;
/// a `PermissionRequest` hook POSTs and *waits* for our reply, so the user can allow/deny from the notch.
final class AgentMonitor {
    static let changed = Notification.Name("ClipStackAgentsChanged")
    static let permissionRequested = Notification.Name("ClipStackAgentPermission")
    static let port: UInt16 = 48766

    struct Session {
        let id: String
        var name: String          // project folder name
        var state: State = .working
        var lastTool: String = ""
        var message: String = ""
        var updated = Date()
        enum State: String { case working, waiting, idle }
    }

    struct Permission {
        let id = UUID()
        let sessionID: String
        let tool: String
        let summary: String
        let connection: NWConnection
        let received = Date()
    }

    private(set) var sessions: [String: Session] = [:]
    private(set) var pending: [Permission] = []
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "ClipStack.agents")

    var waiting: Bool { !pending.isEmpty }
    var activeSessions: [Session] { sessions.values.filter { Date().timeIntervalSince($0.updated) < 3600 }.sorted { $0.updated > $1.updated } }

    init() { start() }

    // MARK: Server

    private func start() {
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
            listener = try NWListener(using: params)
        } catch {
            NSLog("ClipStack: agent listener failed: \(error)"); return
        }
        listener?.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener?.stateUpdateHandler = { st in if case .failed(let e) = st { NSLog("ClipStack: agent listener: \(e)") } }
        listener?.start(queue: queue)
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        readRequest(c, buffer: Data())
    }

    private func readRequest(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            if let r = Self.parse(buf) {
                self.handle(path: r.path, body: r.body, connection: c)
            } else if done || err != nil {
                c.cancel()
            } else {
                self.readRequest(c, buffer: buf)
            }
        }
    }

    private static func parse(_ d: Data) -> (path: String, body: Data)? {
        guard let sep = d.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let head = String(decoding: d[..<sep.lowerBound], as: UTF8.self)
        let lines = head.components(separatedBy: "\r\n")
        let path = lines.first?.components(separatedBy: " ").dropFirst().first ?? "/"
        let len = lines.compactMap { l -> Int? in
            let p = l.components(separatedBy: ":"); return p.count == 2 && p[0].lowercased() == "content-length" ? Int(p[1].trimmingCharacters(in: .whitespaces)) : nil
        }.first ?? 0
        let body = d[sep.upperBound...]
        guard body.count >= len else { return nil }
        return (path, Data(body.prefix(len)))
    }

    private func respond(_ c: NWConnection, json: String) {
        let payload = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n" + json
        c.send(content: Data(payload.utf8), completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: Hook payloads

    private func handle(path: String, body: Data, connection: NWConnection) {
        let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let sid = obj["session_id"] as? String ?? "unknown"
        let cwd = obj["cwd"] as? String ?? ""
        let event = obj["hook_event_name"] as? String ?? path
        let tool = obj["tool_name"] as? String ?? ""
        let input = obj["tool_input"] as? [String: Any] ?? [:]
        let summary = Self.summarize(tool: tool, input: input)

        DispatchQueue.main.async {
            var s = self.sessions[sid] ?? Session(id: sid, name: (cwd as NSString).lastPathComponent.isEmpty ? "Claude Code" : (cwd as NSString).lastPathComponent)
            s.updated = Date()
            switch event {
            case "PermissionRequest":
                s.state = .waiting
                s.lastTool = tool
                s.message = summary
                self.pending.append(Permission(sessionID: sid, tool: tool, summary: summary, connection: connection))
                self.sessions[sid] = s
                NotificationCenter.default.post(name: Self.permissionRequested, object: self)
                NotificationCenter.default.post(name: Self.changed, object: self)
                return  // reply later, when the user decides
            case "Stop", "SubagentStop":
                s.state = .idle; s.message = "Finished"
            case "Notification":
                let msg = obj["message"] as? String ?? ""
                s.message = msg
                s.state = msg.localizedCaseInsensitiveContains("permission") || msg.localizedCaseInsensitiveContains("waiting") ? .waiting : s.state
            case "SessionStart":
                s.state = .working; s.message = "Session started"
            case "UserPromptSubmit":
                s.state = .working; s.message = "Thinking…"
            default:   // PreToolUse / PostToolUse
                s.state = .working; s.lastTool = tool; s.message = summary
            }
            self.sessions[sid] = s
            NotificationCenter.default.post(name: Self.changed, object: self)
        }
        respond(connection, json: "{}")
    }

    private static func summarize(tool: String, input: [String: Any]) -> String {
        if let c = input["command"] as? String { return c }
        if let p = input["file_path"] as? String { return (p as NSString).lastPathComponent }
        if let p = input["pattern"] as? String { return p }
        if let u = input["url"] as? String { return u }
        return tool
    }

    // MARK: Decisions

    func decide(_ p: Permission, allow: Bool) {
        pending.removeAll { $0.id == p.id }
        let json: String
        if allow {
            json = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#
        } else {
            json = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from ClipStack"}}}"#
        }
        respond(p.connection, json: json)
        if var s = sessions[p.sessionID] { s.state = allow ? .working : .idle; s.message = allow ? "Approved: \(p.summary)" : "Denied: \(p.summary)"; s.updated = Date(); sessions[p.sessionID] = s }
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    // MARK: Hook installation (Claude Code ~/.claude/settings.json)

    static let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")

    static var hooksInstalled: Bool {
        guard let d = try? Data(contentsOf: settingsURL), let s = String(data: d, encoding: .utf8) else { return false }
        return s.contains("127.0.0.1:\(port)")
    }

    /// Merges our hooks into ~/.claude/settings.json (backing the file up first). Existing hooks are kept.
    static func installHooks() throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if let d = try? Data(contentsOf: settingsURL), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
            root = o
            try? fm.copyItem(at: settingsURL, to: settingsURL.appendingPathExtension("clipstack-backup"))
        }
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let base = "http://127.0.0.1:\(port)"
        func entry(_ cmd: String) -> [String: Any] { ["hooks": [["type": "command", "command": cmd]]] }
        let post = "curl -s -m 2 -X POST \(base)/event -H 'Content-Type: application/json' --data-binary @- >/dev/null 2>&1; exit 0"
        let perm = "curl -s -m 900 -X POST \(base)/permission -H 'Content-Type: application/json' --data-binary @- 2>/dev/null || echo '{}'"
        for ev in ["SessionStart", "UserPromptSubmit", "PostToolUse", "Notification", "Stop", "SubagentStop"] {
            var list = hooks[ev] as? [[String: Any]] ?? []
            list.removeAll { ($0.description).contains("127.0.0.1:\(port)") }
            list.append(entry(post))
            hooks[ev] = list
        }
        var permList = hooks["PermissionRequest"] as? [[String: Any]] ?? []
        permList.removeAll { ($0.description).contains("127.0.0.1:\(port)") }
        permList.append(entry(perm))
        hooks["PermissionRequest"] = permList
        root["hooks"] = hooks
        try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: settingsURL)
    }
}
