import Foundation

/// 把 App 裡的訂閱、規則、設定轉成 mihomo 的 config.yaml
enum ConfigBuilder {
    static let proxyGroup = "代理"
    static let autoGroup = "自動選擇"
    static let localProvider = "local"

    static func q(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ") + "\""
    }

    static func providerFile(_ name: String, workDir: URL) -> URL {
        workDir.appendingPathComponent("providers/\(name)" + (name == localProvider ? ".txt" : ".yaml"))
    }

    /// 回傳設定檔內容，並把本機節點寫到 providers/local.txt
    static func build(_ store: Store, workDir: URL, tun: Bool = false) -> String {
        let st = store.settings
        let fm = FileManager.default
        try? fm.createDirectory(at: workDir.appendingPathComponent("providers"), withIntermediateDirectories: true)

        var providerNames: [String] = []
        var providerYAML = ""
        let health = "    health-check:\n      enable: true\n      url: \(q(st.testURL))\n      interval: 600\n      lazy: true\n"

        for sub in store.subscriptions where sub.enabled {
            let url = sub.url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { continue }
            let cached = fm.fileExists(atPath: providerFile(sub.providerName, workDir: workDir).path)
            providerNames.append(sub.providerName)
            providerYAML += "  \(q(sub.providerName)):\n"
            providerYAML += "    type: http\n"
            providerYAML += "    url: \(q(url))\n"
            providerYAML += "    path: ./providers/\(sub.providerName).yaml\n"
            providerYAML += "    interval: \(sub.autoUpdate ? max(1, sub.intervalHours) * 3600 : 0)\n"
            // 第一次下載時還沒有節點可用，只能直連
            providerYAML += "    proxy: \(sub.viaProxy && cached ? q(proxyGroup) : "DIRECT")\n"
            providerYAML += health
        }

        let links = store.localLinks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let localURL = providerFile(localProvider, workDir: workDir)
        if links.isEmpty {
            try? fm.removeItem(at: localURL)
        } else {
            try? links.joined(separator: "\n").write(to: localURL, atomically: true, encoding: .utf8)
            providerNames.append(localProvider)
            providerYAML += "  \(localProvider):\n    type: file\n    path: ./providers/\(localProvider).txt\n" + health
        }

        let tunBlock = tun ? "tun:\n  enable: true\n  stack: mixed\n  auto-route: true\n  auto-detect-interface: true\n  dns-hijack: [\"any:53\"]\n" : ""
        let fakeIPBlock = tun ? "  listen: 127.0.0.1:1053\n  enhanced-mode: fake-ip\n  fake-ip-range: 198.18.0.1/16\n  fake-ip-filter: [\"*.lan\", \"*.local\", \"time.*.com\", \"+.pool.ntp.org\", \"time.apple.com\", \"+.push.apple.com\"]\n" : ""

        var y = """
        # 由 Sky 自動產生，手動修改會被覆蓋
        mixed-port: \(st.mixedPort)
        allow-lan: \(st.allowLan)
        bind-address: "*"
        mode: \(st.mode)
        log-level: \(st.logLevel)
        ipv6: false
        external-controller: 127.0.0.1:\(st.controllerPort)
        secret: \(q(st.secret))
        find-process-mode: always
        unified-delay: true
        tcp-concurrent: true
        geo-auto-update: false
        geodata-mode: false
        profile:
          store-selected: true
        \(tunBlock)dns:
          enable: true
          ipv6: false
        \(fakeIPBlock)  default-nameserver: [223.5.5.5, 119.29.29.29, 1.1.1.1]
          nameserver:
            - https://223.5.5.5/dns-query
            - https://1.1.1.1/dns-query

        """

        if !providerYAML.isEmpty {
            y += "proxy-providers:\n" + providerYAML
        }

        let use = providerNames.map(q).joined(separator: ", ")
        y += "proxy-groups:\n"
        if providerNames.isEmpty {
            y += "  - name: \(q(proxyGroup))\n    type: select\n    proxies: [DIRECT]\n"
        } else {
            y += "  - name: \(q(proxyGroup))\n    type: select\n    proxies: [\(q(autoGroup))]\n    use: [\(use)]\n"
            y += "  - name: \(q(autoGroup))\n    type: url-test\n    use: [\(use)]\n    url: \(q(st.testURL))\n    interval: 300\n    tolerance: 50\n    lazy: true\n"
        }

        func target(_ p: RulePolicy) -> String {
            (p == .auto && providerNames.isEmpty) ? proxyGroup : p.target
        }

        y += "rules:\n"
        for r in store.rules where r.enabled {
            let payload = r.payload.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
            guard !payload.isEmpty else { continue }
            var line = "\(r.type),\(payload),\(target(r.policy))"
            if ["IP-CIDR", "IP-CIDR6", "GEOIP"].contains(r.type) { line += ",no-resolve" }
            y += "  - \(q(line))\n"
        }
        y += "  - \(q("MATCH,\(target(st.defaultPolicy))"))\n"
        return y
    }
}
