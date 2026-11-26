import AppKit
import Foundation
import ServiceManagement

enum Page: String, CaseIterable, Identifiable {
    case overview, nodes, subscriptions, rules, connections, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .nodes: return "節點"
        case .subscriptions: return "訂閱"
        case .rules: return "規則"
        case .connections: return "連線"
        case .settings: return "設定"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "house"
        case .nodes: return "server.rack"
        case .subscriptions: return "square.3.layers.3d"
        case .rules: return "slider.horizontal.3"
        case .connections: return "waveform.path.ecg"
        case .settings: return "gearshape"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let workDir: URL
    let core: CoreProcess
    private var storeURL: URL { workDir.appendingPathComponent("state.json") }

    @Published var store: Store { didSet { save() } }
    @Published var page: Page = .overview

    @Published var coreReady = false
    @Published var coreVersion = ""
    @Published var coreError: String?
    @Published var systemProxyOn = false
    @Published var connectedSince: Date?
    @Published var busy = false

    @Published var proxies: [String: ProxyInfo] = [:]
    @Published var providers: [String: ProviderInfo] = [:]
    @Published var testingDelay = false
    @Published var updatingSubs: Set<UUID> = []
    @Published var toast: String?
    let fileServer = LocalFileServer()
    private var lastBuilt: ConfigBuilder.Built?

    /// 由選單列圖示設定，用來在主視窗關掉後重新打開它
    var openMainWindow: (() -> Void)?

    /// 每秒更新的資料放這裡，避免整個畫面每秒重畫
    let live = LiveStats()
    @Published var tunActive = false
    @Published var appUpdate: AppUpdate?
    @Published var coreUpdate: CoreUpdate?
    @Published var checkingUpdates = false
    @Published var coreUpdating = false
    /// 「代理」對應的策略組（設定檔模式時是訂閱的第一個策略組）
    @Published var mainGroup = ConfigBuilder.proxyGroup
    @Published var currentSSID: String?

    /// 進入指定 Wi-Fi 前的模式與連線狀態，離開時恢復
    var ssidSaved: (mode: String, proxy: Bool)?
    private var lastTotals: (Date, Int64, Int64)?
    private var lastConnBytes: [String: (Int64, Int64)] = [:]
    private var loop: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    var api: MihomoAPI { MihomoAPI(port: store.settings.controllerPort, secret: store.settings.secret) }

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        // SKY_HOME：測試時用另一個資料夾，不影響正式設定
        if let home = ProcessInfo.processInfo.environment["SKY_HOME"] {
            workDir = URL(fileURLWithPath: home, isDirectory: true)
        } else {
            workDir = base.appendingPathComponent("Sky", isDirectory: true)
        }
        if let p = ProcessInfo.processInfo.environment["SKY_PAGE"], let pg = Page(rawValue: p) { page = pg }
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        core = CoreProcess(workDir: workDir)
        let url = workDir.appendingPathComponent("state.json")
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Store.self, from: d) {
            store = s
        } else {
            store = Store()
            save()
        }
    }

    private func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(store) { try? d.write(to: storeURL, options: .atomic) }
    }

    func showToast(_ s: String) {
        toast = s
        toastTask?.cancel()
        toastTask = Task { try? await Task.sleep(nanoseconds: 2_500_000_000); if !Task.isCancelled { toast = nil } }
    }

    /// 顯示主視窗：還在（只是被隱藏或縮到 Dock）就拿到最前面，已經關掉就重新打開
    func showMainWindow() {
        let main = NSApp.windows.first { w in
            (w.identifier?.rawValue.hasPrefix("main") ?? false) && w.canBecomeMain
        }
        if let main {
            if main.isMiniaturized { main.deminiaturize(nil) }
            main.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 啟動 / 結束

    func bootstrap() async {
        copyGeoData()
        migrateSubscriptions()
        core.killStale()
        let dir = workDir
        fileServer.resolver = { name in ConfigBuilder.providerFile(name, workDir: dir) }
        // 用 SKY_HOME 測試時不跳提示，避免卡住
        if core.hasLegacySetuid && !core.isDaemonInstalled && ProcessInfo.processInfo.environment["SKY_HOME"] == nil {
            promptLegacyUpgrade()
        }
        await startCore()
        startWatchdog()
        startLoop()
        autoUpdateSubscriptions()
        if store.settings.ssidEnabled { enableSSID(true) }
        let port = store.settings.mixedPort
        let pointing = await Task.detached { SystemProxy.isPointing(to: port) }.value
        if store.settings.autoConnect || pointing {
            await connect()
        }
        autoCheckUpdatesIfNeeded()
    }

    /// 沿用 Clash Verge 已下載的 GeoIP / GeoSite 資料庫，省得再去 GitHub 下載
    private func copyGeoData() {
        let fm = FileManager.default
        let verge = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("io.github.clash-verge-rev.clash-verge-rev")
        for f in ["Country.mmdb", "geoip.dat", "geosite.dat", "ASN.mmdb"] {
            let dst = workDir.appendingPathComponent(f)
            let src = verge.appendingPathComponent(f)
            if !fm.fileExists(atPath: dst.path), fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    // MARK: - TUN 背景服務

    /// TUN 背景服務已安裝：核心由系統以 root 執行，App 透過 API 推送設定
    var daemonMode: Bool { core.isDaemonInstalled }

    /// 開了 TUN 而且背景服務已安裝，才真的寫進設定檔
    var wantTun: Bool { store.settings.tun && daemonMode }

    /// 舊版 1.0.x 的 setuid 授權有提權風險，啟動時請使用者升級或移除
    private func promptLegacyUpgrade() {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "需要升級 TUN 授權"
        a.informativeText = "舊版 Sky 用「setuid」方式授權 mihomo 核心，電腦上任何程式都能利用它免密碼取得最高權限。新版改用系統背景服務，比較安全。\n\n升級或移除都需要輸入一次管理員密碼。"
        a.addButton(withTitle: "立即升級")
        a.addButton(withTitle: "移除舊授權")
        a.addButton(withTitle: "稍後")
        switch a.runModal() {
        case .alertFirstButtonReturn:
            let r = core.installDaemon(controllerPort: store.settings.controllerPort, secret: store.settings.secret)
            showToast(r.ok ? "已升級為 TUN 背景服務" : "升級失敗：\(r.message)")
        case .alertSecondButtonReturn:
            let r = core.uninstallDaemon()
            store.settings.tun = false
            showToast(r.ok ? "已移除舊授權" : "移除失敗：\(r.message)")
        default:
            showToast("舊授權仍在，TUN 暫時停用；可以到「設定」升級")
        }
    }

    /// 產生設定檔並在背景執行緒檢查（mihomo -t 約 0.5 秒，放主執行緒會讓畫面凍結）
    private func writeConfig() async -> (Bool, String) {
        if daemonMode { fileServer.start() }
        let built = ConfigBuilder.build(store, workDir: workDir, tun: wantTun,
                                        fileServer: daemonMode ? fileServer.baseURL : nil)
        mainGroup = built.mainGroup
        lastBuilt = built
        do { try built.yaml.write(to: core.configURL, atomically: true, encoding: .utf8) } catch {
            return (false, "寫入設定檔失敗：\(error.localizedDescription)")
        }
        let core = self.core
        return await Task.detached { core.test() }.value
    }

    private func waitForCore(seconds: Double) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let v = try? await api.version() { coreVersion = v; return true }
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
        return false
    }

    /// 背景服務模式：把設定內容推給 root 核心，並請它重新下載 Sky 提供的節點來源
    private func pushConfig() async throws {
        guard let b = lastBuilt else { return }
        try await api.reload(payload: b.yaml)
        for name in b.providerNames { try? await api.updateProvider(name) }
    }

    func startCore() async {
        coreReady = false
        coreError = nil
        let (ok, msg) = await writeConfig()
        guard ok else { coreError = "設定檔有誤：\(msg)"; return }
        if daemonMode {
            core.stop()   // 一般模式的子行程如果還在，會跟背景服務搶埠口
            guard await waitForCore(seconds: 8) else {
                coreError = "TUN 背景服務沒有回應，可以到「設定」重新安裝或移除：" + core.tailLog(3)
                return
            }
            do { try await pushConfig() } catch {
                coreError = "推送設定到背景服務失敗：\(error.localizedDescription)"
                return
            }
        } else {
            do { try core.start() } catch { coreError = "無法啟動核心：\(error.localizedDescription)"; return }
            guard await waitForCore(seconds: 6) else {
                coreError = "核心沒有回應：" + core.tailLog(3)
                return
            }
        }
        coreReady = true
        tunActive = wantTun
        updateConnectedSince()
        try? await api.select(group: "GLOBAL", name: mainGroup)
        lastTotals = nil
        await refreshProxies()
        refreshSubStatuses()
    }

    func restartCore() async {
        busy = true
        if daemonMode {
            _ = try? await api.request("/restart", method: "POST")
            try? await Task.sleep(nanoseconds: 800_000_000)
        } else {
            core.stop()
        }
        await startCore()
        busy = false
        if systemProxyOn { await connect() }
        showToast(coreReady ? "核心已重新啟動" : "核心啟動失敗")
    }

    /// 修改訂閱或規則之後重新產生設定檔並熱重載
    func applyConfig() async {
        busy = true
        defer { busy = false }
        guard coreReady, daemonMode || core.isRunning else { await startCore(); return }
        let (ok, msg) = await writeConfig()
        guard ok else { showToast("設定檔有誤"); coreError = "設定檔有誤：\(msg)"; return }
        do {
            if daemonMode { try await pushConfig() } else { try await api.reload(path: core.configURL.path) }
            coreError = nil
        } catch {
            coreError = "重新載入失敗：\(error.localizedDescription)"
        }
        tunActive = wantTun
        updateConnectedSince()
        try? await api.select(group: "GLOBAL", name: mainGroup)
        await refreshProxies()
        refreshSubStatuses()
    }

    func shutdown() {
        loop?.cancel()
        if systemProxyOn { SystemProxy.disable() }
        if daemonMode {
            // 背景服務的核心會繼續存在；結束 App 時把 TUN 關掉，避免 App 不在了流量還被接管
            api.patchSync(["tun": ["enable": false]])
        }
        core.stop()
    }

    // MARK: - 守門程式：App 異常結束時關掉系統代理

    private var watchdog: Process?

    /// 背景 shell：等 App 結束後，如果系統代理還指著 Sky 的埠口、而且那個埠口已經沒有核心在聽，就把系統代理關掉，
    /// 避免 App 當掉或被強制結束後整台電腦斷網。（TUN 背景服務模式下核心還活著，就不會關。）
    func startWatchdog() {
        watchdog?.terminate()
        let pid = ProcessInfo.processInfo.processIdentifier
        let port = store.settings.mixedPort
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 3; done
        nc -z 127.0.0.1 \(port) 2>/dev/null && exit 0
        /usr/sbin/networksetup -listallnetworkservices | tail -n +2 | grep -v '^\\*' | while IFS= read -r s; do
          info="$(/usr/sbin/networksetup -getwebproxy "$s")"
          if echo "$info" | grep -q 'Enabled: Yes' && echo "$info" | grep -q 'Port: \(port)$'; then
            /usr/sbin/networksetup -setwebproxystate "$s" off
            /usr/sbin/networksetup -setsecurewebproxystate "$s" off
            /usr/sbin/networksetup -setsocksfirewallproxystate "$s" off
          fi
        done
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        watchdog = p
    }

    /// 設定頁的「重設系統代理」：不管目前狀態，直接把所有網路服務的代理關掉
    func resetSystemProxy() {
        Task {
            await Task.detached { SystemProxy.disable() }.value
            systemProxyOn = false
            updateConnectedSince()
            showToast("已關閉所有網路服務的系統代理")
        }
    }

    // MARK: - 連線（系統代理）

    func connect() async {
        let port = store.settings.mixedPort
        await Task.detached { SystemProxy.enable(port: port) }.value
        systemProxyOn = true
        if connectedSince == nil { connectedSince = Date() }
    }

    func disconnect() async {
        await Task.detached { SystemProxy.disable() }.value
        systemProxyOn = false
        updateConnectedSince()
    }

    /// 系統代理或 TUN 任一開著就算已連線
    var isConnected: Bool { systemProxyOn || tunActive }

    /// 目前用哪種方式連線
    var connectionMode: String? {
        switch (systemProxyOn, tunActive) {
        case (true, true): return "系統代理＋TUN"
        case (false, true): return "TUN"
        case (true, false): return "系統代理"
        default: return nil
        }
    }

    var connectionLabel: String { connectionMode.map { "已連線 · \($0)" } ?? "未連線" }

    private func updateConnectedSince() {
        if isConnected { if connectedSince == nil { connectedSince = Date() } } else { connectedSince = nil }
    }

    /// 已連線就全部中斷（系統代理與 TUN），否則開系統代理
    func toggleConnection() {
        Task {
            if isConnected {
                if systemProxyOn { await disconnect() }
                if store.settings.tun { await setTun(false) }
            } else {
                await connect()
            }
        }
    }

    func setMode(_ m: String) {
        store.settings.mode = m
        Task {
            try? await api.setMode(m)
            try? await api.closeAll()
        }
    }

    // MARK: - 定時更新

    /// 主視窗或選單列面板正在顯示（看不到時把輪詢放慢，省電）
    var menuPanelOpen = false
    private var uiVisible: Bool {
        menuPanelOpen || NSApp.windows.contains { w in
            (w.identifier?.rawValue.hasPrefix("main") ?? false) && w.isVisible && w.occlusionState.contains(.visible)
        }
    }

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            let start = Date()
            var due: [String: Date] = [
                "proxies": start, "nodeTest": start + 30, "subs": start + 45,
                "rules": start + 20, "ssid": start + 2, "daemon": start + 5, "log": start + 60,
            ]
            func run(_ key: String, every: TimeInterval) -> Bool {
                guard Date() >= (due[key] ?? .distantPast) else { return false }
                due[key] = Date() + every
                return true
            }
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                if run("proxies", every: 5) { await self.refreshProxies() }
                if run("nodeTest", every: 60) { await self.testCurrentNode() }
                if run("subs", every: 60) { self.autoUpdateSubscriptions() }
                if run("rules", every: 300) { await self.refreshEmptyRuleProviders() }
                if run("ssid", every: 5) { await self.checkSSID() }
                if run("daemon", every: 5) { await self.checkDaemon() }
                if run("log", every: 300), self.daemonMode { self.core.trimDaemonLog() }
                // 畫面看得到每秒更新；看不到時每 5 秒一次
                let interval: UInt64 = self.uiVisible ? 1 : 5
                try? await Task.sleep(nanoseconds: interval * 1_000_000_000)
            }
        }
    }

    /// 背景服務模式：launchd 重啟核心後設定會回到啟動用的精簡版（沒有代理埠），偵測到就重新推送
    private func checkDaemon() async {
        guard daemonMode, !busy else { return }
        guard let cfg = try? await api.configs() else {
            if coreReady { coreReady = false; coreError = "TUN 背景服務沒有回應，等待它重新啟動…" }
            return
        }
        let port = cfg["mixed-port"] as? Int ?? 0
        if !coreReady || port != store.settings.mixedPort { await startCore() }
    }

    private func tick() async {
        guard coreReady else { return }
        guard let r = try? await api.connections() else {
            if !daemonMode && !core.isRunning { coreReady = false; coreError = "核心已停止：" + core.tailLog(3) }
            return
        }
        let now = Date()
        if let (t, d, u) = lastTotals {
            let dt = max(0.2, now.timeIntervalSince(t))
            live.downSpeed = max(0, Double(r.downloadTotal - d) / dt)
            live.upSpeed = max(0, Double(r.uploadTotal - u) / dt)
        }
        lastTotals = (now, r.downloadTotal, r.uploadTotal)
        var hist = live.history
        hist.append(SpeedSample(date: now, down: live.downSpeed, up: live.upSpeed))
        if hist.count > 300 { hist.removeFirst(hist.count - 300) }
        live.history = hist

        let conns = r.connections ?? []
        var newHist: [String: [SpeedSample]] = [:]
        var newBytes: [String: (Int64, Int64)] = [:]
        for c in conns {
            let prev = lastConnBytes[c.id]
            let s = SpeedSample(date: now,
                                down: prev.map { Double(max(0, c.download - $0.0)) } ?? 0,
                                up: prev.map { Double(max(0, c.upload - $0.1)) } ?? 0)
            var h = live.connHistory[c.id] ?? []
            h.append(s)
            if h.count > 120 { h.removeFirst(h.count - 120) }
            newHist[c.id] = h
            newBytes[c.id] = (c.download, c.upload)
        }
        live.connHistory = newHist
        lastConnBytes = newBytes
        if live.activeCount != conns.count { live.activeCount = conns.count }
        if !live.pausedConnections {
            // ISO 時間字串可以直接比較大小，不必每次比較都解析成日期
            live.connections = conns.sorted { ($0.start ?? "") > ($1.start ?? "") }
        }
    }

    func refreshProxies() async {
        guard coreReady else { return }
        guard var merged = try? await api.proxies() else { return }
        if let p = try? await api.providers() {
            if p != providers { providers = p }
            // /proxies 不含節點來源裡的節點；把它們（含延遲紀錄）合併進來
            var map: [String: String] = [:]
            for (k, v) in p where v.isUserProvider {
                for x in v.proxies ?? [] {
                    map[x.name] = k
                    if merged[x.name] == nil { merged[x.name] = x }
                }
            }
            nodeProvider = map
        }
        // 內容沒變就不要觸發畫面重畫
        if merged != proxies { proxies = merged }
    }

    // MARK: - 節點與策略組

    static let groupTypes: Set<String> = ["Selector", "URLTest", "Fallback", "LoadBalance", "Relay"]

    func isGroup(_ name: String) -> Bool { proxies[name].map { AppState.groupTypes.contains($0.type) } ?? false }

    var currentGroupNow: String? { proxies[mainGroup]?.now }

    /// 實際在用的節點（一路往下找到不是策略組的那個）
    var currentNode: String? { resolve(mainGroup) }

    func resolve(_ group: String) -> String? {
        guard var n = proxies[group]?.now else { return nil }
        var guardCount = 0
        while let p = proxies[n], let next = p.now, guardCount < 8 { n = next; guardCount += 1 }
        return n
    }

    var currentDelay: Int? { currentNode.flatMap { proxies[$0]?.lastDelay } }

    /// 可以在節點頁選擇的策略組（依設定檔順序，主要策略組排第一）
    var groups: [String] {
        var list = (proxies["GLOBAL"]?.all ?? []).filter { isGroup($0) }
        if list.isEmpty, proxies[mainGroup] != nil { list = [mainGroup] }
        if let i = list.firstIndex(of: mainGroup) { list.remove(at: i); list.insert(mainGroup, at: 0) }
        return list
    }

    /// 節點屬於哪個來源（找伺服器資訊用）
    private(set) var nodeProvider: [String: String] = [:]

    func members(of group: String) -> [NodeItem] {
        (proxies[group]?.all ?? []).map { n in
            let h = proxies[n]?.history ?? []
            return NodeItem(name: n, type: proxies[n]?.type ?? "—", provider: nodeProvider[n] ?? "", delay: h.last?.delay, history: h)
        }
    }

    /// 節點詳情用的檔案（訂閱設定檔或節點來源檔）
    func detailFile(for node: NodeItem) -> URL? {
        if node.provider.hasPrefix("sub-") || node.provider == ConfigBuilder.localProvider {
            return ConfigBuilder.providerFile(node.provider, workDir: workDir)
        }
        if let prof = ConfigBuilder.profileSub(store, workDir: workDir) {
            if !node.provider.isEmpty {
                // 訂閱自己內嵌的節點來源，mihomo 會存在設定檔指定的 path
                let guess = core.dataDir.appendingPathComponent("proxies/\(node.provider).yaml")
                if FileManager.default.fileExists(atPath: guess.path) { return guess }
            }
            return ConfigBuilder.subFile(prof, workDir: workDir)
        }
        return nil
    }

    func providerDisplayName(_ key: String) -> String {
        if key == ConfigBuilder.localProvider { return "本機節點" }
        if let s = store.subscriptions.first(where: { $0.providerName == key }) { return s.name }
        if let prof = ConfigBuilder.profileSub(store, workDir: workDir) {
            return key.isEmpty ? prof.name : "\(prof.name) · \(key)"
        }
        return key.isEmpty ? "—" : key
    }

    func select(_ node: String, in group: String? = nil) {
        let g = group ?? mainGroup
        Task {
            do {
                try await api.select(group: g, name: node)
                try? await api.closeAll()
                await refreshProxies()
                showToast("\(g) → \(Flags.cleanName(node))")
                await refreshEmptyRuleProviders()
            } catch {
                showToast("切換失敗：\(error.localizedDescription)")
            }
        }
    }

    /// 規則集第一次下載失敗（例如當時還沒選節點）時，mihomo 要等更新間隔才會重試；這裡主動補抓空的
    func refreshEmptyRuleProviders() async {
        guard coreReady,
              let d = try? await api.request("/providers/rules"),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let provs = obj["providers"] as? [String: [String: Any]] else { return }
        let empty = provs.filter { ($0.value["ruleCount"] as? Int ?? 0) == 0 }.map(\.key)
        await withTaskGroup(of: Void.self) { g in
            for name in empty {
                g.addTask { _ = try? await self.api.request("/providers/rules/\(MihomoAPI.enc(name))", method: "PUT", timeout: 30) }
            }
        }
    }

    func testGroup(_ group: String) {
        guard !testingDelay else { return }
        testingDelay = true
        Task {
            _ = try? await api.groupDelay(group, url: store.settings.testURL)
            await refreshProxies()
            testingDelay = false
            showToast("延遲測試完成")
        }
    }

    func testDelay(_ name: String) {
        Task {
            _ = await api.delay(name, provider: nodeProvider[name], url: store.settings.testURL)
            await refreshProxies()
        }
    }

    private func testCurrentNode() async {
        guard let n = currentNode, n != "DIRECT" else { return }
        _ = await api.delay(n, provider: nodeProvider[n], url: store.settings.testURL)
    }

    func toggleFavorite(_ name: String) {
        if let i = store.favorites.firstIndex(of: name) { store.favorites.remove(at: i) } else { store.favorites.append(name) }
    }

    func addLocalLinks(_ text: String) {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.contains("://") }
        guard !lines.isEmpty else { showToast("沒有找到節點連結"); return }
        store.localLinks.append(contentsOf: lines)
        Task { await applyConfig(); showToast("已新增 \(lines.count) 個節點") }
    }

    // MARK: - 訂閱（由 Sky 自己下載，才能拿到完整設定檔與流量資訊）

    var profileSub: Subscription? { ConfigBuilder.profileSub(store, workDir: workDir) }

    func subNodeCount(_ s: Subscription) -> Int? {
        guard FileManager.default.fileExists(atPath: ConfigBuilder.subFile(s, workDir: workDir).path) else { return nil }
        if s.id == profileSub?.id {
            // 設定檔：內嵌節點＋它自己的節點來源
            let ours = Set(store.subscriptions.map(\.providerName) + [ConfigBuilder.localProvider, "default"])
            let fromProviders = providers.values.filter { !ours.contains($0.name) && $0.isUserProvider }.reduce(0) { $0 + ($1.proxies?.count ?? 0) }
            let inline = summary(s)?.inline ?? 0
            return inline + fromProviders
        }
        return providers[s.providerName]?.proxies?.count
    }

    func subUpdatedAt(_ s: Subscription) -> Date? { s.updatedAt.map { Date(timeIntervalSince1970: $0) } }

    func subInfo(_ s: Subscription) -> SubInfo? {
        guard let t = s.total, t > 0 else { return nil }
        return SubInfo(Upload: s.upload, Download: s.download, Total: t, Expire: s.expire)
    }

    private struct ProfileSummary { let stamp: Double; let groups: [String]; let rules: [String]; let inline: Int }
    private var profileCache: [UUID: ProfileSummary] = [:]

    /// 解析過的訂閱檔摘要；訂閱更新（updatedAt 變了）才重新讀檔，避免畫面每次重畫都解析
    private func summary(_ s: Subscription) -> ProfileSummary? {
        let stamp = s.updatedAt ?? 0
        if let c = profileCache[s.id], c.stamp == stamp { return c }
        guard let t = try? String(contentsOf: ConfigBuilder.subFile(s, workDir: workDir), encoding: .utf8) else { return nil }
        let p = ProfileText(t)
        let c = ProfileSummary(stamp: stamp, groups: p.groupNames(), rules: p.rules(), inline: p.inlineProxyCount)
        profileCache[s.id] = c
        return c
    }

    /// 訂閱設定檔的策略組名稱
    func profileGroups(_ s: Subscription) -> [String] { summary(s)?.groups ?? [] }

    func profileRules(_ s: Subscription) -> [String] { summary(s)?.rules ?? [] }

    private func refreshSubStatuses() {
        for i in store.subscriptions.indices where store.subscriptions[i].enabled && store.subscriptions[i].statusOK == nil {
            let ok = (subNodeCount(store.subscriptions[i]) ?? 0) > 0
            store.subscriptions[i].statusOK = ok
            store.subscriptions[i].statusMessage = ok ? "更新成功" : "還沒有節點"
        }
    }

    /// 舊版把訂閱存在 providers/，搬到 subs/
    func migrateSubscriptions() {
        let fm = FileManager.default
        try? fm.createDirectory(at: workDir.appendingPathComponent("subs"), withIntermediateDirectories: true)
        for i in store.subscriptions.indices {
            let s = store.subscriptions[i]
            let dst = ConfigBuilder.subFile(s, workDir: workDir)
            let old = workDir.appendingPathComponent("providers/\(s.providerName).yaml")
            if !fm.fileExists(atPath: dst.path), fm.fileExists(atPath: old.path) {
                try? fm.moveItem(at: old, to: dst)
                if store.subscriptions[i].updatedAt == nil {
                    store.subscriptions[i].updatedAt = ((try? dst.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()).timeIntervalSince1970
                }
            }
            if let t = try? String(contentsOf: dst, encoding: .utf8) {
                let full = ProfileText(t).isFullProfile
                if store.subscriptions[i].isProfile != full { store.subscriptions[i].isProfile = full }
            }
        }
    }

    /// 下載一個訂閱：存檔、解析流量資訊、判斷是不是完整設定檔
    private func download(_ s: Subscription) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: s.url.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw APIError(status: 0, body: "連結格式不對") }
        let proxyPort = (s.viaProxy && coreReady && currentNode != nil && currentNode != "DIRECT") ? store.settings.mixedPort : nil
        var r = URLRequest(url: url, timeoutInterval: 30)
        r.setValue("clash.meta mihomo/\(coreVersion.isEmpty ? "1.19" : coreVersion)", forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await Updater.session(proxyPort: proxyPort).data(for: r)
        guard let h = resp as? HTTPURLResponse else { throw APIError(status: 0, body: "沒有回應") }
        guard h.statusCode == 200 else { throw APIError(status: h.statusCode, body: "伺服器拒絕") }
        guard !d.isEmpty else { throw APIError(status: 200, body: "內容是空的") }
        return (d, h)
    }

    func updateSubscription(_ id: UUID, apply: Bool = true) {
        guard let s = store.subscriptions.first(where: { $0.id == id }), !s.url.isEmpty else { return }
        updatingSubs.insert(id)
        Task {
            defer { updatingSubs.remove(id) }
            do {
                let (data, resp) = try await download(s)
                let file = ConfigBuilder.subFile(s, workDir: workDir)
                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                guard let i = store.subscriptions.firstIndex(where: { $0.id == id }) else { return }
                let text = String(data: data, encoding: .utf8) ?? ""
                store.subscriptions[i].isProfile = ProfileText(text).isFullProfile
                store.subscriptions[i].updatedAt = Date().timeIntervalSince1970
                if let info = resp.value(forHTTPHeaderField: "subscription-userinfo") {
                    var kv: [String: Int64] = [:]
                    for part in info.split(separator: ";") {
                        let p = part.split(separator: "=").map { $0.trimmingCharacters(in: .whitespaces) }
                        if p.count == 2, let v = Int64(p[1]) ?? Double(p[1]).map({ Int64($0) }) { kv[p[0].lowercased()] = v }
                    }
                    store.subscriptions[i].upload = kv["upload"]
                    store.subscriptions[i].download = kv["download"]
                    store.subscriptions[i].total = kv["total"]
                    store.subscriptions[i].expire = kv["expire"]
                }
                if apply { await applyConfig() }
                let count = subNodeCount(store.subscriptions[i]) ?? 0
                let isProf = store.subscriptions[i].isProfile
                setStatus(id, ok: true, msg: isProf ? "更新成功（完整設定檔）" : (count > 0 ? "更新成功，\(count) 個節點" : "更新成功"))
            } catch {
                setStatus(id, ok: false, msg: "更新失敗：\(error.localizedDescription)")
            }
        }
    }

    func updateAllSubscriptions() {
        for s in store.subscriptions where s.enabled && !s.url.isEmpty { updateSubscription(s.id) }
    }

    /// 依各訂閱的更新間隔自動更新；沒有檔案的立刻下載
    func autoUpdateSubscriptions() {
        let now = Date().timeIntervalSince1970
        for s in store.subscriptions where s.enabled && !s.url.isEmpty && !updatingSubs.contains(s.id) {
            let missing = !FileManager.default.fileExists(atPath: ConfigBuilder.subFile(s, workDir: workDir).path)
            let due = s.autoUpdate && now - (s.updatedAt ?? 0) > Double(max(1, s.intervalHours) * 3600)
            if missing || due { updateSubscription(s.id) }
        }
    }

    private func setStatus(_ id: UUID, ok: Bool, msg: String) {
        guard let i = store.subscriptions.firstIndex(where: { $0.id == id }) else { return }
        store.subscriptions[i].statusOK = ok
        store.subscriptions[i].statusMessage = msg
    }

    // MARK: - 連線

    func closeConnection(_ id: String) { Task { try? await api.closeConnection(id) } }
    func closeAllConnections() { Task { try? await api.closeAll(); showToast("已中斷全部連線") } }

    var terminalCommand: String {
        let p = store.settings.mixedPort
        return "export https_proxy=http://127.0.0.1:\(p) http_proxy=http://127.0.0.1:\(p) all_proxy=socks5://127.0.0.1:\(p)"
    }

    func copyTerminalCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(terminalCommand, forType: .string)
        showToast("已複製終端代理命令")
    }

    // MARK: - 開機啟動

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            showToast("設定開機啟動失敗：\(error.localizedDescription)")
        }
        objectWillChange.send()
    }
}
