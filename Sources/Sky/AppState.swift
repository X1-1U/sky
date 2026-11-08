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
    @Published var connections: [Conn] = []
    @Published var activeCount = 0
    @Published var downSpeed: Double = 0
    @Published var upSpeed: Double = 0
    @Published var history: [SpeedSample] = []
    @Published var connHistory: [String: [SpeedSample]] = [:]
    @Published var pausedConnections = false
    @Published var testingDelay = false
    @Published var updatingSubs: Set<UUID> = []
    @Published var toast: String?
    @Published var tunActive = false
    @Published var appUpdate: AppUpdate?
    @Published var coreUpdate: CoreUpdate?
    @Published var checkingUpdates = false
    @Published var coreUpdating = false

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

    // MARK: - 啟動 / 結束

    func bootstrap() async {
        copyGeoData()
        core.killStale()
        await startCore()
        startLoop()
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

    /// 開了 TUN 而且核心有授權，才真的寫進設定檔
    var wantTun: Bool { store.settings.tun && core.isTunAuthorized }

    private func writeConfig() -> (Bool, String) {
        let yaml = ConfigBuilder.build(store, workDir: workDir, tun: wantTun)
        do { try yaml.write(to: core.configURL, atomically: true, encoding: .utf8) } catch {
            return (false, "寫入設定檔失敗：\(error.localizedDescription)")
        }
        let core = self.core
        return core.test()
    }

    func startCore() async {
        coreReady = false
        coreError = nil
        let (ok, msg) = writeConfig()
        guard ok else { coreError = "設定檔有誤：\(msg)"; return }
        do { try core.start() } catch { coreError = "無法啟動核心：\(error.localizedDescription)"; return }
        for _ in 0..<60 {
            if let v = try? await api.version() { coreVersion = v; coreReady = true; break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard coreReady else {
            coreError = "核心沒有回應：" + core.tailLog(3)
            return
        }
        tunActive = wantTun
        try? await api.select(group: "GLOBAL", name: ConfigBuilder.proxyGroup)
        lastTotals = nil
        await refreshProxies()
        refreshSubStatuses()
    }

    func restartCore() async {
        busy = true
        core.stop()
        await startCore()
        busy = false
        if systemProxyOn { await connect() }
        showToast(coreReady ? "核心已重新啟動" : "核心啟動失敗")
    }

    /// 修改訂閱或規則之後重新產生設定檔並熱重載
    func applyConfig() async {
        busy = true
        defer { busy = false }
        guard coreReady, core.isRunning else { await startCore(); return }
        // TUN 開關變了要整個重啟核心
        if tunActive != wantTun { core.stop(); await startCore(); return }
        let (ok, msg) = writeConfig()
        guard ok else { showToast("設定檔有誤"); coreError = "設定檔有誤：\(msg)"; return }
        do {
            try await api.reload(path: core.configURL.path)
            coreError = nil
        } catch {
            coreError = "重新載入失敗：\(error.localizedDescription)"
        }
        try? await api.select(group: "GLOBAL", name: ConfigBuilder.proxyGroup)
        await refreshProxies()
        refreshSubStatuses()
    }

    func shutdown() {
        loop?.cancel()
        if systemProxyOn { SystemProxy.disable() }
        core.stop()
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
        connectedSince = nil
    }

    func toggleConnection() {
        Task { systemProxyOn ? await disconnect() : await connect() }
    }

    func setMode(_ m: String) {
        store.settings.mode = m
        Task {
            try? await api.setMode(m)
            try? await api.closeAll()
        }
    }

    // MARK: - 定時更新

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            var n = 0
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                if n % 5 == 0 { await self.refreshProxies() }
                if n % 60 == 30 { await self.testCurrentNode() }
                n += 1
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func tick() async {
        guard coreReady else { return }
        guard let r = try? await api.connections() else {
            if !core.isRunning { coreReady = false; coreError = "核心已停止：" + core.tailLog(3) }
            return
        }
        let now = Date()
        if let (t, d, u) = lastTotals {
            let dt = max(0.2, now.timeIntervalSince(t))
            downSpeed = max(0, Double(r.downloadTotal - d) / dt)
            upSpeed = max(0, Double(r.uploadTotal - u) / dt)
        }
        lastTotals = (now, r.downloadTotal, r.uploadTotal)
        history.append(SpeedSample(date: now, down: downSpeed, up: upSpeed))
        if history.count > 300 { history.removeFirst(history.count - 300) }

        let conns = r.connections ?? []
        var newHist: [String: [SpeedSample]] = [:]
        var newBytes: [String: (Int64, Int64)] = [:]
        for c in conns {
            let prev = lastConnBytes[c.id]
            let s = SpeedSample(date: now,
                                down: prev.map { Double(max(0, c.download - $0.0)) } ?? 0,
                                up: prev.map { Double(max(0, c.upload - $0.1)) } ?? 0)
            var h = connHistory[c.id] ?? []
            h.append(s)
            if h.count > 120 { h.removeFirst(h.count - 120) }
            newHist[c.id] = h
            newBytes[c.id] = (c.download, c.upload)
        }
        connHistory = newHist
        lastConnBytes = newBytes
        activeCount = conns.count
        if !pausedConnections {
            connections = conns.sorted { ($0.startDate ?? .distantPast) > ($1.startDate ?? .distantPast) }
        }
    }

    func refreshProxies() async {
        guard coreReady else { return }
        if let p = try? await api.proxies() { proxies = p }
        if let p = try? await api.providers() { providers = p }
    }

    // MARK: - 節點

    var currentGroupNow: String? { proxies[ConfigBuilder.proxyGroup]?.now }

    /// 實際在用的節點（自動選擇時取它選中的那個）
    var currentNode: String? {
        guard var n = currentGroupNow else { return nil }
        var guardCount = 0
        while let p = proxies[n], let next = p.now, guardCount < 5 { n = next; guardCount += 1 }
        return n
    }

    var currentDelay: Int? { currentNode.flatMap { proxies[$0]?.lastDelay } }

    var nodes: [NodeItem] {
        var out: [NodeItem] = []
        var seen = Set<String>()
        let order = store.subscriptions.map(\.providerName) + [ConfigBuilder.localProvider]
        for key in order {
            guard let prov = providers[key], prov.isUserProvider else { continue }
            for p in prov.proxies ?? [] where !seen.contains(p.name) {
                seen.insert(p.name)
                let live = proxies[p.name]
                let h = live?.history ?? p.history ?? []
                out.append(NodeItem(name: p.name, type: p.type, provider: key, delay: h.last?.delay, history: h))
            }
        }
        return out
    }

    func providerDisplayName(_ key: String) -> String {
        if key == ConfigBuilder.localProvider { return "本機節點" }
        return store.subscriptions.first { $0.providerName == key }?.name ?? key
    }

    func select(_ node: String) {
        Task {
            do {
                try await api.select(group: ConfigBuilder.proxyGroup, name: node)
                try? await api.closeAll()
                await refreshProxies()
                showToast("已切換到 \(Flags.cleanName(node))")
            } catch {
                showToast("切換失敗：\(error.localizedDescription)")
            }
        }
    }

    func testAllDelays() {
        guard !testingDelay else { return }
        testingDelay = true
        Task {
            let url = store.settings.testURL
            let names = nodes.map(\.name)
            await withTaskGroup(of: Void.self) { g in
                var i = 0
                for n in names {
                    if i >= 16 { await g.next() }   // 同時最多 16 個
                    g.addTask { _ = await self.api.delay(n, url: url) }
                    i += 1
                }
            }
            await refreshProxies()
            testingDelay = false
            showToast("延遲測試完成")
        }
    }

    func testDelay(_ name: String) {
        Task {
            _ = await api.delay(name, url: store.settings.testURL)
            await refreshProxies()
        }
    }

    private func testCurrentNode() async {
        guard let n = currentNode, n != "DIRECT" else { return }
        _ = await api.delay(n, url: store.settings.testURL)
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

    // MARK: - 訂閱

    func subNodeCount(_ s: Subscription) -> Int? { providers[s.providerName]?.proxies?.count }
    func subUpdatedAt(_ s: Subscription) -> Date? { providers[s.providerName]?.updatedAt.flatMap(Fmt.parseDate) }
    func subInfo(_ s: Subscription) -> SubInfo? {
        guard let i = providers[s.providerName]?.subscriptionInfo, (i.Total ?? 0) > 0 else { return nil }
        return i
    }

    private func refreshSubStatuses() {
        for i in store.subscriptions.indices where store.subscriptions[i].enabled {
            let s = store.subscriptions[i]
            guard !s.url.isEmpty else { continue }
            let count = subNodeCount(s) ?? 0
            let ok = count > 0
            if store.subscriptions[i].statusOK != ok {
                store.subscriptions[i].statusOK = ok
                store.subscriptions[i].statusMessage = ok ? "更新成功" : "更新失敗，請檢查連結"
            }
        }
    }

    func updateSubscription(_ id: UUID) {
        guard let s = store.subscriptions.first(where: { $0.id == id }) else { return }
        updatingSubs.insert(id)
        Task {
            defer { updatingSubs.remove(id) }
            if providers[s.providerName] == nil {
                await applyConfig()      // 新訂閱還沒寫進設定檔
            } else {
                do {
                    try await api.updateProvider(s.providerName)
                } catch {
                    setStatus(id, ok: false, msg: "更新失敗：\(error.localizedDescription)")
                    return
                }
            }
            await refreshProxies()
            let ok = (subNodeCount(s) ?? 0) > 0
            setStatus(id, ok: ok, msg: ok ? "更新成功" : "更新失敗，請檢查連結")
        }
    }

    func updateAllSubscriptions() {
        for s in store.subscriptions where s.enabled && !s.url.isEmpty { updateSubscription(s.id) }
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
