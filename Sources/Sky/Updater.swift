import AppKit
import Foundation

struct GHAsset: Decodable { let name: String; let browser_download_url: String }
struct GHRelease: Decodable { let tag_name: String; let html_url: String; let body: String?; let assets: [GHAsset] }

struct AppUpdate { let version: String; let url: String; let notes: String }
struct CoreUpdate { let version: String; let url: String; let name: String }

enum Updater {
    static let appRepo = "X1-1U/sky"
    static let coreRepo = "MetaCubeX/mihomo"

    static var appVersion: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0" }

    static func compare(_ a: String, _ b: String) -> Int {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(whereSeparator: { $0 == "." || $0 == "-" }).map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l - r }
        }
        return 0
    }

    /// 對外請求：核心在跑時走 mihomo，GitHub 被擋時也能連
    static func session(proxyPort: Int?) -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        if let p = proxyPort {
            c.connectionProxyDictionary = [
                "HTTPEnable": true, "HTTPProxy": "127.0.0.1", "HTTPPort": p,
                "HTTPSEnable": true, "HTTPSProxy": "127.0.0.1", "HTTPSPort": p,
            ]
        }
        return URLSession(configuration: c)
    }

    static func latest(_ repo: String, session: URLSession) async throws -> GHRelease {
        var r = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("Sky-Updater", forHTTPHeaderField: "User-Agent")
        let (d, resp) = try await session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 404 { throw APIError(status: 404, body: "找不到發佈版本") }
        guard code == 200 else { throw APIError(status: code, body: "") }
        return try JSONDecoder().decode(GHRelease.self, from: d)
    }
}

extension AppState {
    private var updateSession: URLSession { Updater.session(proxyPort: coreReady ? store.settings.mixedPort : nil) }

    func checkUpdates(silent: Bool) async {
        guard !checkingUpdates else { return }
        checkingUpdates = true
        defer {
            checkingUpdates = false
            store.settings.lastUpdateCheck = Date().timeIntervalSince1970
        }
        let session = updateSession
        var errors: [String] = []
        do {
            let rel = try await Updater.latest(Updater.appRepo, session: session)
            if Updater.compare(rel.tag_name, Updater.appVersion) > 0 {
                let asset = rel.assets.first { $0.name.lowercased().contains("mac") && $0.name.hasSuffix(".zip") }
                appUpdate = AppUpdate(version: rel.tag_name, url: asset?.browser_download_url ?? rel.html_url, notes: rel.body ?? "")
            } else { appUpdate = nil }
        } catch { errors.append("App：\(error.localizedDescription)") }
        do {
            let rel = try await Updater.latest(Updater.coreRepo, session: session)
            let want = "mihomo-darwin-arm64-\(rel.tag_name).gz"
            if !coreVersion.isEmpty, Updater.compare(rel.tag_name, coreVersion) > 0,
               let a = rel.assets.first(where: { $0.name == want }) {
                coreUpdate = CoreUpdate(version: rel.tag_name, url: a.browser_download_url, name: a.name)
            } else { coreUpdate = nil }
        } catch { errors.append("mihomo：\(error.localizedDescription)") }
        if !silent {
            if appUpdate == nil && coreUpdate == nil {
                showToast(errors.isEmpty ? "已經是最新版本" : "檢查更新失敗：\(errors[0])")
            }
        }
    }

    func autoCheckUpdatesIfNeeded() {
        guard store.settings.autoCheckUpdates,
              Date().timeIntervalSince1970 - store.settings.lastUpdateCheck > 86400 else { return }
        Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            await checkUpdates(silent: true)
        }
    }

    func openAppUpdate() {
        if let u = appUpdate, let url = URL(string: u.url) { NSWorkspace.shared.open(url) }
    }

    /// 下載新版 mihomo，驗證可以執行後替換並重啟核心
    func updateCore() async {
        guard let u = coreUpdate, !coreUpdating else { return }
        coreUpdating = true
        defer { coreUpdating = false }
        let fm = FileManager.default
        let tmp = workDir.appendingPathComponent("bin/download", isDirectory: true)
        try? fm.removeItem(at: tmp)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        do {
            let (file, resp) = try await updateSession.download(from: URL(string: u.url)!)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw APIError(status: (resp as? HTTPURLResponse)?.statusCode ?? 0, body: "下載失敗") }
            let gz = tmp.appendingPathComponent(u.name)
            try fm.moveItem(at: file, to: gz)
            let exe = tmp.appendingPathComponent("mihomo")
            // gunzip -c 檔案 > mihomo
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
            p.arguments = ["-c", gz.path]
            fm.createFile(atPath: exe.path, contents: nil)
            p.standardOutput = try FileHandle(forWritingTo: exe)
            try p.run(); p.waitUntilExit()
            guard p.terminationStatus == 0 else { throw APIError(status: 0, body: "解壓縮失敗") }
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
            // 確認新核心能執行
            let v = Process()
            v.executableURL = exe
            v.arguments = ["-v"]
            let pipe = Pipe()
            v.standardOutput = pipe
            try v.run(); v.waitUntilExit()
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard v.terminationStatus == 0, out.contains("Mihomo") else { throw APIError(status: 0, body: "新核心無法執行") }

            core.stop()
            try fm.createDirectory(at: core.updatedBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: core.updatedBinary)
            try fm.copyItem(at: exe, to: core.updatedBinary)
            if core.isTunAuthorized {
                // TUN 授權版也要換成新的，需要再輸入一次密碼
                let r = core.authorizeTun(from: core.updatedBinary)
                if !r.ok { showToast("TUN 核心沒有更新：\(r.message)") }
            }
            await startCore()
            if systemProxyOn { await connect() }
            coreUpdate = nil
            showToast("mihomo 已更新到 \(coreVersion)")
        } catch {
            showToast("更新核心失敗：\(error.localizedDescription)")
            if !core.isRunning { await startCore() }
        }
    }

    // MARK: - TUN

    func setTun(_ on: Bool) async {
        if on && !core.isTunAuthorized {
            core.stop()
            let r = core.authorizeTun()
            if !r.ok {
                showToast("沒有啟用 TUN：\(r.message)")
                await startCore()
                return
            }
        }
        store.settings.tun = on
        await restartCore()
        showToast(on ? (tunActive ? "TUN 模式已開啟" : "TUN 開啟失敗，請查看日誌") : "TUN 模式已關閉")
    }

    func revokeTun() async {
        store.settings.tun = false
        core.stop()
        let r = core.revokeTun()
        await startCore()
        if systemProxyOn { await connect() }
        showToast(r.ok ? "已移除 TUN 授權" : "移除授權失敗：\(r.message)")
    }
}
