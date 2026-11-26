import AppKit
import CryptoKit
import Foundation

/// digest 是 GitHub 提供的 "sha256:..."（2025 年中以後上傳的檔案都有）
struct GHAsset: Decodable { let name: String; let browser_download_url: String; let digest: String? }
struct GHRelease: Decodable { let tag_name: String; let html_url: String; let body: String?; let assets: [GHAsset] }

struct AppUpdate { let version: String; let url: String; let notes: String }
struct CoreUpdate { let version: String; let url: String; let name: String; let sha256: String }

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
                // 沒有官方雜湊值就不提供更新，避免裝到被調包的核心
                if let d = a.digest, d.hasPrefix("sha256:") {
                    coreUpdate = CoreUpdate(version: rel.tag_name, url: a.browser_download_url, name: a.name, sha256: String(d.dropFirst(7)))
                } else {
                    coreUpdate = nil
                    errors.append("mihomo：新版 \(rel.tag_name) 沒有提供 SHA-256，略過")
                }
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
            // 比對官方 SHA-256，不符就拒絕
            let hash = SHA256.hash(data: try Data(contentsOf: gz)).map { String(format: "%02x", $0) }.joined()
            guard hash == u.sha256.lowercased() else {
                throw APIError(status: 0, body: "SHA-256 不符，已拒絕安裝（可能被調包）")
            }
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

            try fm.createDirectory(at: core.updatedBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: core.updatedBinary)
            try fm.copyItem(at: exe, to: core.updatedBinary)
            if daemonMode {
                // 背景服務用的核心也要換，需要輸入一次管理員密碼
                let r = core.updateDaemonBinary(from: core.updatedBinary)
                if !r.ok { showToast("TUN 背景服務的核心沒有更新：\(r.message)") }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            } else {
                core.stop()
            }
            await startCore()
            if systemProxyOn { await connect() }
            coreUpdate = nil
            showToast("mihomo 已更新到 \(coreVersion)")
        } catch {
            showToast("更新核心失敗：\(error.localizedDescription)")
            if !daemonMode && !core.isRunning { await startCore() }
        }
    }

    // MARK: - TUN

    /// 開 TUN：第一次會安裝背景服務（輸入一次管理員密碼）；之後開關只是重新推送設定
    func setTun(_ on: Bool) async {
        if on && !daemonMode {
            core.stop()
            let r = core.installDaemon(controllerPort: store.settings.controllerPort, secret: store.settings.secret)
            if !r.ok {
                showToast("沒有啟用 TUN：\(r.message)")
                await startCore()
                return
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            store.settings.tun = true
            await startCore()
        } else {
            store.settings.tun = on
            await applyConfig()
        }
        if systemProxyOn { await connect() }
        showToast(on ? (tunActive ? "TUN 模式已開啟" : "TUN 開啟失敗，請查看日誌") : "TUN 模式已關閉")
    }

    /// 移除背景服務（也會清掉舊版 setuid 核心），改回一般模式
    func revokeTun() async {
        store.settings.tun = false
        let r = core.uninstallDaemon()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await startCore()
        if systemProxyOn { await connect() }
        showToast(r.ok ? "已移除 TUN 背景服務" : "移除失敗：\(r.message)")
    }

    /// 設定頁的「升級授權」：把舊版 setuid 核心換成背景服務
    func upgradeLegacyTun() async {
        let r = core.installDaemon(controllerPort: store.settings.controllerPort, secret: store.settings.secret)
        try? await Task.sleep(nanoseconds: 800_000_000)
        await startCore()
        showToast(r.ok ? "已升級為 TUN 背景服務" : "升級失敗：\(r.message)")
    }
}
