import Foundation

/// 把 App 裡的訂閱、規則、設定轉成 mihomo 的 config.yaml
///
/// 兩種情況：
/// - 有訂閱是完整設定檔（有策略組與規則）且開了「使用訂閱的分組與規則」→ 以它為底，蓋掉 Sky 要掌控的鍵，
///   自訂規則放最前面，其他訂閱與本機節點放進「其他節點」策略組
/// - 否則 → 所有訂閱當節點來源，Sky 自己建「代理」「自動選擇」兩個策略組
enum ConfigBuilder {
    static let proxyGroup = "代理"
    static let autoGroup = "自動選擇"
    static let extraGroup = "其他節點"
    static let localProvider = "local"

    struct Built {
        let yaml: String
        let mainGroup: String
        let autoGroup: String
        let profile: Subscription?
    }

    static func q(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ") + "\""
    }

    /// 訂閱下載後存放的位置
    static func subFile(_ sub: Subscription, workDir: URL) -> URL {
        workDir.appendingPathComponent("subs/\(sub.id.uuidString.lowercased()).yaml")
    }

    static func providerFile(_ name: String, workDir: URL) -> URL {
        if name == localProvider { return workDir.appendingPathComponent("providers/local.txt") }
        return workDir.appendingPathComponent("subs/\(name.replacingOccurrences(of: "sub-", with: "")).yaml")
    }

    /// 目前當作底稿的訂閱
    static func profileSub(_ store: Store, workDir: URL) -> Subscription? {
        store.subscriptions.first { s in
            s.enabled && s.useProfile && s.isProfile && FileManager.default.fileExists(atPath: subFile(s, workDir: workDir).path)
        }
    }

    private static func ruleLines(_ store: Store, target: (RulePolicy) -> String) -> [String] {
        store.rules.filter(\.enabled).compactMap { r in
            let payload = r.payload.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            guard !payload.isEmpty else { return nil }
            var line = "\(r.type),\(payload),\(target(r.policy))"
            if ["IP-CIDR", "IP-CIDR6", "GEOIP"].contains(r.type) { line += ",no-resolve" }
            return q(line)
        }
    }

    private static func health(_ st: AppSettings) -> String {
        "health-check: {enable: true, url: \(q(st.testURL)), interval: 600, lazy: true}"
    }

    private static func overrides(_ st: AppSettings, tun: Bool) -> String {
        var y = """
        mixed-port: \(st.mixedPort)
        allow-lan: \(st.allowLan)
        bind-address: "*"
        mode: \(st.mode)
        log-level: \(st.logLevel)
        external-controller: 127.0.0.1:\(st.controllerPort)
        secret: \(q(st.secret))
        find-process-mode: always
        profile:
          store-selected: true

        """
        if tun {
            y += "tun:\n  enable: true\n  stack: mixed\n  auto-route: true\n  auto-detect-interface: true\n  dns-hijack: [\"any:53\"]\n"
        }
        return y
    }

    private static func dnsBlock(tun: Bool) -> String {
        var y = "dns:\n  enable: true\n  ipv6: false\n"
        if tun {
            y += "  enhanced-mode: fake-ip\n  fake-ip-range: 198.18.0.1/16\n"
            y += "  fake-ip-filter: [\"*.lan\", \"*.local\", \"time.*.com\", \"+.pool.ntp.org\", \"time.apple.com\", \"+.push.apple.com\"]\n"
        }
        y += "  default-nameserver: [223.5.5.5, 119.29.29.29, 1.1.1.1]\n  nameserver:\n    - https://223.5.5.5/dns-query\n    - https://1.1.1.1/dns-query\n"
        return y
    }

    /// 本機節點寫到 providers/local.txt，回傳是否有
    private static func writeLocal(_ store: Store, workDir: URL) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: workDir.appendingPathComponent("providers"), withIntermediateDirectories: true)
        let links = store.localLinks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let url = providerFile(localProvider, workDir: workDir)
        if links.isEmpty { try? fm.removeItem(at: url); return false }
        try? links.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    static func build(_ store: Store, workDir: URL, tun: Bool = false) -> Built {
        let st = store.settings
        let fm = FileManager.default
        let hasLocal = writeLocal(store, workDir: workDir)
        let profile = profileSub(store, workDir: workDir)

        // 一般節點來源（設定檔模式時是「其他」訂閱）
        let providerSubs = store.subscriptions.filter { s in
            s.enabled && s.id != profile?.id && fm.fileExists(atPath: subFile(s, workDir: workDir).path)
        }
        var providerNames = providerSubs.map(\.providerName)
        if hasLocal { providerNames.append(localProvider) }
        func providerEntry(_ name: String) -> String {
            let path = name == localProvider ? "./providers/local.txt" : "./subs/\(name.replacingOccurrences(of: "sub-", with: "")).yaml"
            return "\(q(name)): {type: file, path: \(path), \(health(st))}"
        }

        if let profile, let text = try? String(contentsOf: subFile(profile, workDir: workDir), encoding: .utf8) {
            var p = ProfileText(text)
            p.strip(ProfileOverride.stripped)
            let groups = p.groupNames()
            let main = profile.mainGroup.flatMap { groups.contains($0) ? $0 : nil } ?? groups.first ?? "DIRECT"
            let auto = groups.first { $0.contains("自动") || $0.contains("自動") || $0.lowercased().contains("auto") } ?? main
            func target(_ pol: RulePolicy) -> String {
                switch pol {
                case .proxy: return main
                case .auto: return auto
                case .direct: return "DIRECT"
                case .reject: return "REJECT"
                }
            }
            if !providerNames.isEmpty {
                p.addMapEntries(providerNames.map(providerEntry), to: "proxy-providers")
                p.appendItems(["{name: \(q(extraGroup)), type: select, use: [\(providerNames.map(q).joined(separator: ", "))]}"], to: "proxy-groups")
            }
            p.prependItems(ruleLines(store, target: target), to: "rules")
            var y = "# 由 Sky 產生：以訂閱「\(profile.name)」為底稿，Sky 蓋掉埠口、控制 API、TUN 等設定\n"
            y += p.text + "\n\n# ---- Sky ----\n" + overrides(st, tun: tun)
            if !p.has("dns") { y += dnsBlock(tun: tun) }
            return Built(yaml: y, mainGroup: main, autoGroup: auto, profile: profile)
        }

        // 一般模式
        var y = "# 由 Sky 自動產生，手動修改會被覆蓋\n" + overrides(st, tun: tun)
        y += "ipv6: false\nunified-delay: true\ntcp-concurrent: true\ngeo-auto-update: false\n"
        y += dnsBlock(tun: tun)
        if !providerNames.isEmpty {
            y += "proxy-providers:\n" + providerNames.map { "  " + providerEntry($0) + "\n" }.joined()
        }
        let use = providerNames.map(q).joined(separator: ", ")
        y += "proxy-groups:\n"
        if providerNames.isEmpty {
            y += "  - {name: \(q(proxyGroup)), type: select, proxies: [DIRECT]}\n"
        } else {
            y += "  - {name: \(q(proxyGroup)), type: select, proxies: [\(q(autoGroup))], use: [\(use)]}\n"
            y += "  - {name: \(q(autoGroup)), type: url-test, use: [\(use)], url: \(q(st.testURL)), interval: 300, tolerance: 50, lazy: true}\n"
        }
        func target(_ p: RulePolicy) -> String {
            (p == .auto && providerNames.isEmpty) ? proxyGroup : p.target
        }
        y += "rules:\n" + ruleLines(store, target: target).map { "  - \($0)\n" }.joined()
        y += "  - \(q("MATCH,\(target(st.defaultPolicy))"))\n"
        return Built(yaml: y, mainGroup: proxyGroup, autoGroup: providerNames.isEmpty ? proxyGroup : autoGroup, profile: nil)
    }
}
