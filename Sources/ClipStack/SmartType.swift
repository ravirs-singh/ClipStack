import AppKit
import Foundation

/// Detected content category for a clip, plus the text transformations we offer for it.
enum SmartType: String {
    case plain = "Text"
    case richText = "Rich Text"
    case url = "URL"
    case email = "Email"
    case phone = "Phone"
    case color = "Color"
    case json = "JSON"
    case number = "Number"
    case code = "Code"
    case image = "Image"
    case files = "Files"

    var symbol: String {
        switch self {
        case .plain: return "doc.text"
        case .richText: return "doc.richtext"
        case .url: return "link"
        case .email: return "envelope"
        case .phone: return "phone"
        case .color: return "paintpalette"
        case .json: return "curlybraces"
        case .number: return "number"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .image: return "photo"
        case .files: return "folder"
        }
    }

    var tint: NSColor {
        switch self {
        case .url: return .systemBlue
        case .email: return .systemTeal
        case .phone: return .systemGreen
        case .color: return .systemPink
        case .json, .code: return .systemPurple
        case .number: return .systemIndigo
        case .image: return .systemOrange
        case .files: return .systemBrown
        case .plain, .richText: return .secondaryLabelColor
        }
    }

    // MARK: Detection

    static func detect(_ item: ClipItem) -> SmartType {
        switch item.kind {
        case .image: return .image
        case .files: return .files
        case .text: break
        }
        let raw = item.text ?? ""
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return .plain }

        if t.count < 2048 {
            if let c = parseColor(t), c != nil { return .color }
            if isSingleMatch(t, types: .link), t.contains("://") || t.hasPrefix("www.") { return .url }
            if isEmail(t) { return .email }
            if isSingleMatch(t, types: .phoneNumber) { return .phone }
            if Double(t.replacingOccurrences(of: ",", with: "")) != nil { return .number }
        }
        if isJSON(t) { return .json }
        if looksLikeCode(t) { return .code }
        return item.isRich ? .richText : .plain
    }

    private static func isSingleMatch(_ s: String, types: NSTextCheckingResult.CheckingType) -> Bool {
        guard let det = try? NSDataDetector(types: types.rawValue) else { return false }
        let range = NSRange(s.startIndex..., in: s)
        let matches = det.matches(in: s, range: range)
        return matches.count == 1 && matches[0].range == range
    }

    private static func isEmail(_ s: String) -> Bool {
        let re = try! NSRegularExpression(pattern: #"^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#)
        return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    static func isJSON(_ s: String) -> Bool {
        guard let f = s.first, f == "{" || f == "[", let data = s.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func looksLikeCode(_ s: String) -> Bool {
        let lines = s.split(separator: "\n")
        guard lines.count >= 3 else { return false }
        let hints = ["{", "}", ";", "=>", "==", "def ", "func ", "import ", "#include", "class ", "return ", "</", "/>"]
        let hits = hints.reduce(0) { $0 + (s.contains($1) ? 1 : 0) }
        let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        return hits >= 3 || indented * 2 >= lines.count
    }

    /// Parses "#rrggbb", "#rgb", "rgb(r,g,b)" or "rgba(…)". Returns NSColor? wrapped so we can distinguish "no" from "nil".
    static func parseColor(_ s: String) -> NSColor?? {
        let t = s.lowercased()
        if t.hasPrefix("#"), [4, 7, 9].contains(t.count) {
            var hex = String(t.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            guard let v = UInt64(hex, radix: 16) else { return .none }
            let r, g, b, a: CGFloat
            if hex.count == 8 {
                r = CGFloat((v >> 24) & 0xff) / 255; g = CGFloat((v >> 16) & 0xff) / 255
                b = CGFloat((v >> 8) & 0xff) / 255; a = CGFloat(v & 0xff) / 255
            } else {
                r = CGFloat((v >> 16) & 0xff) / 255; g = CGFloat((v >> 8) & 0xff) / 255
                b = CGFloat(v & 0xff) / 255; a = 1
            }
            return .some(NSColor(srgbRed: r, green: g, blue: b, alpha: a))
        }
        if t.hasPrefix("rgb") {
            let nums = t.components(separatedBy: CharacterSet(charactersIn: "(),rgba ")).compactMap { Double($0) }
            guard nums.count == 3 || nums.count == 4 else { return .none }
            return .some(NSColor(srgbRed: nums[0] / 255, green: nums[1] / 255, blue: nums[2] / 255,
                                 alpha: nums.count == 4 ? nums[3] : 1))
        }
        return .none
    }

    // MARK: Transformations

    struct Action {
        let title: String
        let apply: (String) -> String?   // nil = not applicable
    }

    /// Actions offered for this type, applied to the item's plain text.
    func actions() -> [Action] {
        var list: [Action] = []
        switch self {
        case .json:
            list.append(Action(title: "Pretty-print JSON") { Self.prettyJSON($0, pretty: true) })
            list.append(Action(title: "Minify JSON") { Self.prettyJSON($0, pretty: false) })
        case .color:
            list.append(Action(title: "Convert to Hex") { s in
                guard let c = Self.parseColor(s), let c, let rgb = c.usingColorSpace(.sRGB) else { return nil }
                return String(format: "#%02x%02x%02x", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
            })
            list.append(Action(title: "Convert to rgb()") { s in
                guard let c = Self.parseColor(s), let c, let rgb = c.usingColorSpace(.sRGB) else { return nil }
                return "rgb(\(Int(rgb.redComponent * 255)), \(Int(rgb.greenComponent * 255)), \(Int(rgb.blueComponent * 255)))"
            })
        case .url:
            list.append(Action(title: "Strip tracking parameters") { s in
                guard var comps = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
                let junk = ["utm_", "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "igshid"]
                comps.queryItems = comps.queryItems?.filter { q in !junk.contains { q.name.hasPrefix($0) } }
                if comps.queryItems?.isEmpty == true { comps.queryItems = nil }
                return comps.string
            })
        default: break
        }
        list.append(Action(title: "Trim whitespace") { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        list.append(Action(title: "Collapse to one line") {
            $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        })
        list.append(Action(title: "UPPERCASE") { $0.uppercased() })
        list.append(Action(title: "lowercase") { $0.lowercased() })
        list.append(Action(title: "Title Case") { $0.capitalized })
        list.append(Action(title: "Remove duplicate lines") { s in
            var seen = Set<String>()
            return s.components(separatedBy: .newlines).filter { seen.insert($0).inserted }.joined(separator: "\n")
        })
        list.append(Action(title: "Sort lines") { $0.components(separatedBy: .newlines).sorted().joined(separator: "\n") })
        return list
    }

    private static func prettyJSON(_ s: String, pretty: Bool) -> String? {
        guard let data = s.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let out = try? JSONSerialization.data(withJSONObject: obj, options: pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]) else { return nil }
        return String(data: out, encoding: .utf8)
    }

    /// "Open" action target for URL/email/phone types.
    func openURL(for text: String) -> URL? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .url: return URL(string: t.hasPrefix("www.") ? "https://" + t : t)
        case .email: return URL(string: "mailto:" + t)
        case .phone: return URL(string: "tel:" + t.filter { "+0123456789".contains($0) })
        default: return nil
        }
    }
}
