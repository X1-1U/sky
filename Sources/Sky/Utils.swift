import AppKit
import Foundation

enum Fmt {
    static func bytes(_ b: Double) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = max(0, b), i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        if i == 0 { return "\(Int(v)) B" }
        return String(format: v >= 100 ? "%.0f %@" : "%.1f %@", v, units[i])
    }
    static func bytes(_ b: Int64) -> String { bytes(Double(b)) }
    static func speed(_ b: Double) -> String { bytes(b) + "/s" }

    static func duration(_ s: TimeInterval) -> String {
        let t = max(0, Int(s))
        return String(format: "%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60)
    }

    static func ago(_ d: Date?) -> String {
        guard let d else { return "尚未更新" }
        let s = Date().timeIntervalSince(d)
        if s < 60 { return "剛剛" }
        if s < 3600 { return "\(Int(s / 60)) 分鐘前" }
        if s < 86400 { return "\(Int(s / 3600)) 小時前" }
        return "\(Int(s / 86400)) 天前"
    }

    static func delay(_ ms: Int?) -> String {
        guard let ms else { return "—" }
        return ms == 0 ? "逾時" : "\(ms) ms"
    }

    private static let iso1: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    private static let iso2 = ISO8601DateFormatter()

    static func parseDate(_ s: String) -> Date? {
        // mihomo 的小數秒可能有 9 位，先截到 3 位
        var str = s
        if let dot = str.firstIndex(of: "."), let end = str[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let frac = str[str.index(after: dot)..<end]
            if frac.count > 3 { str.replaceSubrange(dot..<end, with: "." + frac.prefix(3)) }
        }
        guard let d = iso1.date(from: str) ?? iso2.date(from: str) else { return nil }
        return d.timeIntervalSince1970 < 946684800 ? nil : d   // 0001-01-01 代表從未
    }

    static let hms: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
    static let hm: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
}

// MARK: - 國旗

enum Flags {
    private static let table: [(String, String)] = [
        ("香港", "HK"), ("Hong Kong", "HK"), ("HongKong", "HK"), ("台灣", "TW"), ("臺灣", "TW"), ("台湾", "TW"), ("Taiwan", "TW"),
        ("日本", "JP"), ("東京", "JP"), ("东京", "JP"), ("大阪", "JP"), ("Japan", "JP"), ("Tokyo", "JP"),
        ("新加坡", "SG"), ("獅城", "SG"), ("狮城", "SG"), ("Singapore", "SG"),
        ("美國", "US"), ("美国", "US"), ("洛杉磯", "US"), ("洛杉矶", "US"), ("矽谷", "US"), ("硅谷", "US"), ("紐約", "US"), ("纽约", "US"), ("United States", "US"),
        ("韓國", "KR"), ("韩国", "KR"), ("首爾", "KR"), ("首尔", "KR"), ("Korea", "KR"),
        ("英國", "GB"), ("英国", "GB"), ("倫敦", "GB"), ("伦敦", "GB"), ("United Kingdom", "GB"),
        ("德國", "DE"), ("德国", "DE"), ("Germany", "DE"), ("法國", "FR"), ("法国", "FR"), ("France", "FR"),
        ("加拿大", "CA"), ("Canada", "CA"), ("澳洲", "AU"), ("澳大利亞", "AU"), ("澳大利亚", "AU"), ("Australia", "AU"),
        ("俄羅斯", "RU"), ("俄罗斯", "RU"), ("Russia", "RU"), ("印度", "IN"), ("India", "IN"), ("土耳其", "TR"), ("Turkey", "TR"),
        ("荷蘭", "NL"), ("荷兰", "NL"), ("Netherlands", "NL"), ("泰國", "TH"), ("泰国", "TH"), ("Thailand", "TH"),
        ("越南", "VN"), ("Vietnam", "VN"), ("馬來", "MY"), ("马来", "MY"), ("Malaysia", "MY"),
        ("菲律賓", "PH"), ("菲律宾", "PH"), ("Philippines", "PH"), ("印尼", "ID"), ("Indonesia", "ID"),
        ("阿根廷", "AR"), ("巴西", "BR"), ("Brazil", "BR"), ("澳門", "MO"), ("澳门", "MO"), ("Macau", "MO"),
        ("瑞士", "CH"), ("意大利", "IT"), ("義大利", "IT"), ("西班牙", "ES"), ("愛爾蘭", "IE"), ("爱尔兰", "IE"),
    ]
    private static let codes = ["HK", "TW", "JP", "SG", "US", "KR", "UK", "GB", "DE", "FR", "CA", "AU", "RU", "IN", "TR", "NL", "TH", "VN", "MY", "PH", "MO"]

    private static var codeCache: [String: String] = [:]
    private static let none = "-"

    /// 有快取：同一個名稱只判斷一次（節點卡片每次重畫都會呼叫）
    static func code(for name: String) -> String? {
        if let c = codeCache[name] { return c == none ? nil : c }
        let c = computeCode(name)
        codeCache[name] = c ?? none
        return c
    }

    private static func computeCode(_ name: String) -> String? {
        // 名稱開頭已經是國旗 emoji
        let scalars = Array(name.unicodeScalars.prefix(2))
        if scalars.count == 2, scalars.allSatisfy({ (0x1F1E6...0x1F1FF).contains($0.value) }) {
            return String(scalars.map { Character(UnicodeScalar($0.value - 0x1F1E6 + 65)!) })
        }
        for (k, c) in table where name.localizedCaseInsensitiveContains(k) { return c }
        for c in codes where name.range(of: "(?<![A-Za-z])\(c)(?![a-z])", options: .regularExpression) != nil {
            return c == "UK" ? "GB" : c
        }
        return nil
    }

    static func emoji(_ code: String) -> String {
        code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map { String($0) }.joined()
    }

    /// 去掉名稱開頭重複的國旗 emoji
    static func cleanName(_ name: String) -> String {
        var s = Substring(name)
        while let f = s.unicodeScalars.first, (0x1F1E6...0x1F1FF).contains(f.value) { s = Substring(s.unicodeScalars.dropFirst()) }
        return s.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - 連線的 App 圖示

enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func bundleURL(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        var url = URL(fileURLWithPath: path)
        var found: URL?
        while url.path != "/" {
            if url.pathExtension == "app" { found = url }   // 取最外層的 .app
            url.deleteLastPathComponent()
        }
        return found
    }

    static func icon(_ path: String?) -> NSImage {
        let key = path ?? ""
        if let i = cache[key] { return i }
        let img: NSImage
        if let b = bundleURL(path) {
            img = NSWorkspace.shared.icon(forFile: b.path)
        } else if let path, !path.isEmpty {
            img = NSWorkspace.shared.icon(forFile: path)
        } else {
            img = NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()
        }
        cache[key] = img
        return img
    }

    private static var nameCache: [String: String] = [:]

    static func name(_ c: Conn) -> String {
        let key = (c.metadata.processPath ?? "") + "|" + (c.metadata.process ?? "")
        if let n = nameCache[key] { return n }
        let n = computeName(c)
        nameCache[key] = n
        return n
    }

    private static func computeName(_ c: Conn) -> String {
        if let b = bundleURL(c.metadata.processPath) {
            return FileManager.default.displayName(atPath: b.path).replacingOccurrences(of: ".app", with: "")
        }
        if let p = c.metadata.process, !p.isEmpty { return p }
        return "未知"
    }

    static func bundleID(_ c: Conn) -> String {
        if let b = bundleURL(c.metadata.processPath), let id = Bundle(url: b)?.bundleIdentifier { return id }
        return c.metadata.processPath ?? "—"
    }
}

// MARK: - 從訂閱檔找出節點的伺服器與連接埠

enum NodeDetails {
    private static var cache: [String: (Date, String)] = [:]

    static func lookup(name: String, file: URL) -> (server: String, port: String)? {
        guard let text = load(file) else { return nil }
        if text.contains("://") && !text.contains("proxies:") {
            return fromLinks(name: name, text: text)
        }
        return fromYAML(name: name, text: text)
    }

    private static func load(_ file: URL) -> String? {
        let mod = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        if let c = cache[file.path], c.0 == mod { return c.1 }
        guard let data = try? Data(contentsOf: file), var s = String(data: data, encoding: .utf8) else { return nil }
        if !s.contains("proxies:") && !s.contains("://"),
           let d = Data(base64Encoded: s.trimmingCharacters(in: .whitespacesAndNewlines).padBase64()),
           let decoded = String(data: d, encoding: .utf8) {
            s = decoded
        }
        cache[file.path] = (mod, s)
        return s
    }

    private static func fromLinks(name: String, text: String) -> (String, String)? {
        for line in text.split(whereSeparator: \.isNewline).map(String.init) {
            if line.hasPrefix("vmess://") {
                let b = String(line.dropFirst(8)).padBase64()
                guard let d = Data(base64Encoded: b), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
                if (j["ps"] as? String) == name { return ("\(j["add"] ?? "—")", "\(j["port"] ?? "—")") }
                continue
            }
            guard let hash = line.lastIndex(of: "#") else { continue }
            let n = String(line[line.index(after: hash)...]).removingPercentEncoding ?? ""
            guard n == name, let c = URLComponents(string: String(line[..<hash])) else { continue }
            return (c.host ?? "—", c.port.map(String.init) ?? "—")
        }
        return nil
    }

    private static func fromYAML(name: String, text: String) -> (String, String)? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let patterns = ["name: \(name)", "name: \"\(name)\"", "name: '\(name)'", "\"name\":\"\(name)\""]
        guard let idx = lines.firstIndex(where: { l in patterns.contains { l.contains($0 + ",") || l.contains($0 + "}") || l.hasSuffix($0) || l.contains($0 + " ") } }) else { return nil }
        func grab(_ key: String, _ s: String) -> String? {
            guard let r = s.range(of: "\(key):\\s*\"?([^,}\"\\s]+)", options: .regularExpression) else { return nil }
            return String(s[r]).replacingOccurrences(of: "\(key):", with: "").trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        }
        if let srv = grab("server", lines[idx]) { return (srv, grab("port", lines[idx]) ?? "—") }
        // 區塊格式：往上找到 "- " 開頭，往下找到下一個 "- "
        var start = idx
        while start > 0 && !lines[start].trimmingCharacters(in: .whitespaces).hasPrefix("-") { start -= 1 }
        var end = idx + 1
        while end < lines.count && !lines[end].trimmingCharacters(in: .whitespaces).hasPrefix("-") { end += 1 }
        let block = lines[start..<end].joined(separator: "\n")
        guard let srv = grab("server", block) else { return nil }
        return (srv, grab("port", block) ?? "—")
    }
}

extension String {
    func padBase64() -> String {
        var s = replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        while s.count % 4 != 0 { s += "=" }
        return s
    }
}

// MARK: - 本機規則比對（給「測試規則」用）

enum RuleMatcher {
    struct Result { let index: Int?; let policy: RulePolicy; let note: String? }

    static func host(from input: String) -> String {
        let t = input.trimmingCharacters(in: .whitespaces)
        let u = URL(string: t.contains("://") ? t : "https://" + t)
        return (u?.host ?? t).lowercased()
    }

    static func match(_ input: String, rules: [Rule], defaultPolicy: RulePolicy) -> Result {
        let h = host(from: input)
        let isIP = ipv4(h) != nil
        var skipped = false
        for (i, r) in rules.enumerated() where r.enabled {
            let p = r.payload.lowercased().trimmingCharacters(in: .whitespaces)
            let hit: Bool
            switch r.type {
            case "DOMAIN": hit = h == p
            case "DOMAIN-SUFFIX": hit = h == p || h.hasSuffix("." + p)
            case "DOMAIN-KEYWORD": hit = h.contains(p)
            case "DOMAIN-REGEX": hit = h.range(of: r.payload, options: .regularExpression) != nil
            case "IP-CIDR": hit = isIP && cidr(h, p)
            default: hit = false; skipped = true
            }
            if hit { return Result(index: i, policy: r.policy, note: nil) }
        }
        return Result(index: nil, policy: defaultPolicy, note: skipped ? "部分規則類型需實際連線才能判斷" : nil)
    }

    static func ipv4(_ s: String) -> UInt32? {
        let parts = s.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }), s.split(separator: ".").count == 4 else { return nil }
        return parts.reduce(0) { $0 << 8 | $1 }
    }

    static func cidr(_ ip: String, _ block: String) -> Bool {
        let comps = block.split(separator: "/")
        guard let a = ipv4(ip), let b = ipv4(String(comps[0])) else { return false }
        let bits = comps.count > 1 ? (UInt32(comps[1]) ?? 32) : 32
        if bits == 0 { return true }
        let mask: UInt32 = bits >= 32 ? .max : ~(UInt32.max >> bits)
        return a & mask == b & mask
    }
}
