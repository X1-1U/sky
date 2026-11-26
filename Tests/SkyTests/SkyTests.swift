import XCTest
@testable import Sky

/// 共用測試檔（Tests/fixtures）
func fixture(_ name: String) -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("fixtures/\(name)")
    return try! String(contentsOf: url, encoding: .utf8)
}

final class ProfileTextTests: XCTestCase {
    func testParsesGroupsRulesAndInlineProxies() {
        let p = ProfileText(fixture("profile-full.yaml"))
        XCTAssertEqual(p.groupNames(), ["默认代理", "AI", "全部手动", "全部自动", "香港故转"])
        XCTAssertEqual(p.rules().count, 4)
        XCTAssertEqual(p.rules().last, "MATCH,默认代理")
        XCTAssertEqual(p.inlineProxyCount, 2)
        XCTAssertEqual(p.ruleProviderCount, 1)
        XCTAssertTrue(p.isFullProfile)
    }

    func testNodesOnlyIsNotFullProfile() {
        let p = ProfileText(fixture("nodes-only.yaml"))
        XCTAssertFalse(p.isFullProfile)
        XCTAssertEqual(p.inlineProxyCount, 2)
    }

    func testStripRemovesKeysSkyControlsAndKeepsTheRest() {
        var p = ProfileText(fixture("profile-full.yaml"))
        p.strip(ProfileOverride.stripped)
        for k in ["mixed-port", "authentication", "skip-auth-prefixes", "external-controller", "secret",
                  "tun", "external-ui", "external-ui-url", "allow-lan", "profile", "log-level"] {
            XCTAssertFalse(p.has(k), "應該拿掉 \(k)")
        }
        for k in ["rule-anchor", "proxy-providers", "proxies", "dns", "proxy-groups", "rules", "rule-providers"] {
            XCTAssertTrue(p.has(k), "應該保留 \(k)")
        }
    }

    func testPrependedRuleUsesSameIndentAndComesFirst() {
        var p = ProfileText(fixture("profile-full.yaml"))
        p.prependItems(["\"DOMAIN,a.example,DIRECT\""], to: "rules")
        XCTAssertEqual(p.rules().first, "DOMAIN,a.example,DIRECT")
        XCTAssertEqual(p.rules().count, 5)
        XCTAssertTrue(p.text.contains("rules:\n  - \"DOMAIN,a.example,DIRECT\"\n  - RULE-SET"))
    }
}

final class ConfigBuilderTests: XCTestCase {
    var dir: URL!
    let subID = UUID(uuidString: "11111111-2222-4333-8444-555555555555")!
    let otherID = UUID(uuidString: "66666666-7777-4888-8999-000000000000")!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("skytests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir.appendingPathComponent("subs"), withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    /// profile：主訂閱是完整設定檔；other：再加一份只有節點的訂閱；local：加一條分享連結
    func makeStore(allowLan: Bool = false, other: Bool = false, local: Bool = false) -> Store {
        var store = Store()
        var sub = Subscription(name: "主訂閱", url: "https://sub.example.invalid/a")
        sub.id = subID
        sub.isProfile = true
        try! fixture("profile-full.yaml").write(to: ConfigBuilder.subFile(sub, workDir: dir), atomically: true, encoding: .utf8)
        store.subscriptions = [sub]
        if other {
            var o = Subscription(name: "其他", url: "https://sub.example.invalid/b")
            o.id = otherID
            try! fixture("nodes-only.yaml").write(to: ConfigBuilder.subFile(o, workDir: dir), atomically: true, encoding: .utf8)
            store.subscriptions.append(o)
        }
        if local { store.localLinks = [fixture("local-links.txt").trimmingCharacters(in: .whitespacesAndNewlines)] }
        store.rules = [Rule(type: "DOMAIN-SUFFIX", payload: "example.com", policy: .proxy)]
        store.settings.allowLan = allowLan
        return store
    }

    func testProfileModeKeepsGroupsAndPutsUserRulesFirst() {
        let b = ConfigBuilder.build(makeStore(), workDir: dir)
        XCTAssertEqual(b.mainGroup, "默认代理")
        XCTAssertEqual(b.autoGroup, "全部自动")
        XCTAssertNotNil(b.profile)
        let y = b.yaml
        let mine = y.range(of: "\"DOMAIN-SUFFIX,example.com,默认代理\"")
        let theirs = y.range(of: "RULE-SET,private_domain")
        XCTAssertNotNil(mine)
        XCTAssertNotNil(theirs)
        XCTAssertLessThan(mine!.lowerBound, theirs!.lowerBound, "自訂規則要在訂閱規則前面")
        XCTAssertTrue(y.contains("external-controller: 127.0.0.1:"))
        XCTAssertFalse(y.contains("0.0.0.0:9090"), "訂閱的控制 API 要被蓋掉")
        XCTAssertFalse(y.contains("external-ui"), "外部面板下載要拿掉")
    }

    func testSubscriptionCredentialsAreDroppedWhenLanIsOff() {
        let y = ConfigBuilder.build(makeStore(allowLan: false), workDir: dir).yaml
        XCTAssertFalse(y.contains("user:secretpass"))
        XCTAssertFalse(y.contains("authentication:"))
    }

    func testLanRequiresSkyCredentialsButLocalhostSkips() {
        let store = makeStore(allowLan: true)
        let y = ConfigBuilder.build(store, workDir: dir).yaml
        XCTAssertTrue(y.contains("allow-lan: true"))
        XCTAssertTrue(y.contains("authentication:\n  - \"\(store.settings.lanUser):\(store.settings.lanPassword)\""))
        XCTAssertTrue(y.contains("skip-auth-prefixes:\n  - 127.0.0.1/8"))
        XCTAssertFalse(y.contains("user:secretpass"), "不能沿用訂閱自己的帳密")
    }

    func testDaemonModeServesProvidersOverLocalhost() {
        let b = ConfigBuilder.build(makeStore(other: true, local: true), workDir: dir, fileServer: "http://127.0.0.1:1234/tok")
        XCTAssertTrue(b.yaml.contains("url: \"http://127.0.0.1:1234/tok/local\""))
        XCTAssertTrue(b.yaml.contains("url: \"http://127.0.0.1:1234/tok/sub-\(otherID.uuidString.lowercased())\""))
        XCTAssertFalse(b.yaml.contains("type: file"), "root 核心不能讀使用者資料夾的檔案")
        XCTAssertEqual(Set(b.providerNames), ["local", "sub-\(otherID.uuidString.lowercased())"])
    }

    func testTunBlockReplacesSubscriptionTun() {
        let y = ConfigBuilder.build(makeStore(), workDir: dir, tun: true).yaml
        XCTAssertTrue(y.contains("tun:\n  enable: true\n  stack: mixed"))
        XCTAssertFalse(y.contains("stack: system"), "訂閱自己的 tun 設定要拿掉")
    }

    /// 產生的每一種設定都交給真正的 mihomo 檢查（找不到核心就略過）
    func testMihomoAcceptsAllGeneratedConfigs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bin = ProcessInfo.processInfo.environment["MIHOMO_BIN"] ?? root.appendingPathComponent("vendor/mihomo").path
        guard FileManager.default.isExecutableFile(atPath: bin) else { throw XCTSkip("找不到 mihomo：\(bin)") }
        let variants: [(String, String)] = [
            ("profile", ConfigBuilder.build(makeStore(), workDir: dir).yaml),
            ("lan", ConfigBuilder.build(makeStore(allowLan: true, other: true, local: true), workDir: dir).yaml),
            ("daemon", ConfigBuilder.build(makeStore(other: true, local: true), workDir: dir, tun: true, fileServer: "http://127.0.0.1:1/t").yaml),
        ]
        for (name, yaml) in variants {
            let f = dir.appendingPathComponent("\(name).yaml")
            try yaml.write(to: f, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-t", "-d", dir.path, "-f", f.path]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            try p.run()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            p.waitUntilExit()
            XCTAssertEqual(p.terminationStatus, 0, "\(name) 設定 mihomo 不接受：\(out.suffix(300))")
        }
    }
}

final class LocalFileServerTests: XCTestCase {
    func testServesOnlyWithTokenAndAllowedNames() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("skyfs-\(UUID().uuidString).txt")
        try "trojan://x@y:1#z".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        let server = LocalFileServer()
        server.resolver = { $0 == "local" ? file : nil }
        server.start()
        let base = try XCTUnwrap(server.baseURL)
        XCTAssertTrue(base.hasPrefix("http://127.0.0.1:"))

        func get(_ url: String) async throws -> (Int, String) {
            let (d, r) = try await URLSession.shared.data(from: URL(string: url)!)
            return ((r as! HTTPURLResponse).statusCode, String(data: d, encoding: .utf8) ?? "")
        }
        let ok = try await get(base + "/local")
        XCTAssertEqual(ok.0, 200)
        XCTAssertEqual(ok.1, "trojan://x@y:1#z")
        let wrongToken = base.replacingOccurrences(of: server.token, with: "nope")
        let r1 = try await get(wrongToken + "/local")
        let r2 = try await get(base + "/state.json")
        let r3 = try await get(base + "/..%2Fstate.json")
        XCTAssertEqual(r1.0, 404, "token 錯誤要拒絕")
        XCTAssertEqual(r2.0, 404, "不在允許清單的檔名要拒絕")
        XCTAssertEqual(r3.0, 404, "路徑跳脫要拒絕")
    }
}
