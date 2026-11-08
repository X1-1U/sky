import Foundation

/// 用文字方式處理訂閱的 mihomo 設定檔（保留錨點、註解與原本格式）
struct ProfileText {
    var lines: [String]

    init(_ text: String) {
        lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    }

    var text: String { lines.joined(separator: "\n") }

    /// 頂層鍵：第 0 欄、不是註解、形如 `key:`
    private static func topKey(_ line: String) -> String? {
        guard let f = line.first, f != " ", f != "\t", f != "#", f != "-" else { return nil }
        guard let r = line.range(of: "^[A-Za-z0-9_.-]+(?=:)", options: .regularExpression) else { return nil }
        return String(line[r])
    }

    /// 每個頂層鍵的範圍（起始行到下一個頂層鍵前）
    func blocks() -> [(key: String, start: Int, end: Int)] {
        var out: [(String, Int, Int)] = []
        for (i, l) in lines.enumerated() {
            if let k = ProfileText.topKey(l) {
                if !out.isEmpty { out[out.count - 1].2 = i }
                out.append((k, i, lines.count))
            }
        }
        return out.map { (key: $0.0, start: $0.1, end: $0.2) }
    }

    func has(_ key: String) -> Bool { blocks().contains { $0.key == key } }

    /// 移除指定的頂層鍵
    mutating func strip(_ keys: Set<String>) {
        for b in blocks().reversed() where keys.contains(b.key) {
            lines.removeSubrange(b.start..<b.end)
        }
    }

    /// 某個區塊底下的清單項目（只取第一層）
    func items(of key: String) -> [String] {
        guard let b = blocks().first(where: { $0.key == key }) else { return [] }
        // 行內格式 key: [a, b]
        let head = lines[b.start]
        if let r = head.range(of: ":\\s*\\[(.*)\\]\\s*$", options: .regularExpression) {
            return String(head[r]).drop(while: { $0 != "[" }).dropFirst().dropLast()
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        var out: [String] = []
        var itemIndent: Int?
        for l in lines[(b.start + 1)..<b.end] {
            let trimmed = l.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = l.prefix(while: { $0 == " " }).count
            guard trimmed.hasPrefix("- ") || trimmed == "-" else { continue }
            if itemIndent == nil { itemIndent = indent }
            if indent == itemIndent { out.append(String(trimmed.dropFirst(2))) }
        }
        return out
    }

    /// 區塊第一層子項目的縮排（沒有就用預設）
    private func childIndent(_ b: (key: String, start: Int, end: Int), list: Bool) -> String {
        for l in lines[(b.start + 1)..<b.end] {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { continue }
            return String(l.prefix(while: { $0 == " " }))
        }
        return list ? "  " : "  "
    }

    /// 在區塊開頭插入清單項目（例如把自訂規則放在最前面）
    mutating func prependItems(_ items: [String], to key: String) {
        guard !items.isEmpty else { return }
        guard let b = blocks().first(where: { $0.key == key }) else {
            lines.append("\(key):")
            lines.append(contentsOf: items.map { "  - \($0)" })
            return
        }
        let ind = childIndent(b, list: true)
        lines.insert(contentsOf: items.map { "\(ind)- \($0)" }, at: b.start + 1)
    }

    /// 在清單區塊結尾加項目
    mutating func appendItems(_ items: [String], to key: String) {
        guard !items.isEmpty else { return }
        guard let b = blocks().first(where: { $0.key == key }) else {
            lines.append("\(key):")
            lines.append(contentsOf: items.map { "  - \($0)" })
            return
        }
        let ind = childIndent(b, list: true)
        var at = b.end
        while at > b.start + 1 && lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
        lines.insert(contentsOf: items.map { "\(ind)- \($0)" }, at: at)
    }

    /// 在對應表區塊加子鍵（例如 proxy-providers 加一個來源），entry 第一行是 `name: {...}` 或多行
    mutating func addMapEntries(_ entries: [String], to key: String) {
        guard !entries.isEmpty else { return }
        guard let b = blocks().first(where: { $0.key == key }) else {
            lines.append("\(key):")
            lines.append(contentsOf: entries.map { "  \($0)" })
            return
        }
        let ind = childIndent(b, list: false)
        lines.insert(contentsOf: entries.map { "\(ind)\($0)" }, at: b.start + 1)
    }

    /// 策略組名稱（依檔案順序）
    func groupNames() -> [String] {
        items(of: "proxy-groups").compactMap(ProfileText.nameOf)
    }

    /// 從 `{name: X, ...}` 或 `name: X` 取名稱
    static func nameOf(_ item: String) -> String? {
        let s = item.hasPrefix("{") ? String(item.dropFirst()) : item
        guard let r = s.range(of: "name:\\s*", options: .regularExpression) else { return nil }
        var rest = s[r.upperBound...]
        if let q = rest.first, q == "\"" || q == "'" {
            rest = rest.dropFirst()
            return rest.firstIndex(of: q).map { String(rest[..<$0]) }
        }
        let end = rest.firstIndex(where: { $0 == "," || $0 == "}" }) ?? rest.endIndex
        let v = rest[..<end].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    /// 規則清單（去掉引號）
    func rules() -> [String] {
        items(of: "rules").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ")) }
    }

    /// 這份訂閱是不是完整的設定檔（有策略組和規則）
    var isFullProfile: Bool { !groupNames().isEmpty && !rules().isEmpty }

    var inlineProxyCount: Int { items(of: "proxies").count }
    var ruleProviderCount: Int {
        guard let b = blocks().first(where: { $0.key == "rule-providers" }) else { return 0 }
        let ind = childIndent(b, list: false).count
        return lines[(b.start + 1)..<b.end].filter { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && !t.hasPrefix("#") && l.prefix(while: { $0 == " " }).count == ind && t.contains(":")
        }.count
    }
}

/// 訂閱設定檔中 Sky 一定要自己掌控的頂層鍵
enum ProfileOverride {
    static let stripped: Set<String> = [
        "port", "socks-port", "redir-port", "tproxy-port", "mixed-port", "authentication", "skip-auth-prefixes",
        "allow-lan", "bind-address", "lan-allowed-ips", "lan-disallowed-ips", "mode", "log-level",
        "external-controller", "external-controller-tls", "external-controller-unix", "external-controller-pipe",
        "external-controller-cors", "external-ui", "external-ui-name", "external-ui-url", "external-doh-server",
        "secret", "tun", "profile", "find-process-mode", "interface-name", "routing-mark",
    ]
}
