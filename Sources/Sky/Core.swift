import Foundation

/// 管理 mihomo 核心。兩種執行方式：
/// - 一般模式：App 以使用者身分啟動子行程（沒有 TUN）
/// - 背景服務模式：TUN 授權後，由系統的 LaunchDaemon 以 root 執行核心。
///   核心程式與工作資料夾都屬於 root（一般程式改不了），App 只透過 API 推送設定，
///   root 核心不會讀寫使用者資料夾裡的檔案。取代舊版的 setuid 做法
///  （setuid 核心任何程式都能拿來以 root 身分執行，等於免密碼提權）。
final class CoreProcess {
    let workDir: URL
    private(set) var process: Process?

    init(workDir: URL) { self.workDir = workDir }

    var configURL: URL { workDir.appendingPathComponent("config.yaml") }
    var logURL: URL { workDir.appendingPathComponent("core.log") }
    private var pidURL: URL { workDir.appendingPathComponent("core.pid") }

    // MARK: - 路徑

    static let rootDir = "/Library/Application Support/Sky"
    static let rootBinary = rootDir + "/mihomo"
    static let rootWork = rootDir + "/work"
    static let daemonLabel = "com.onsunday.sky.core"
    static let daemonPlist = "/Library/LaunchDaemons/\(daemonLabel).plist"
    static let daemonLogDir = "/Library/Logs/Sky"
    static let daemonLog = daemonLogDir + "/core.log"

    /// 檢查更新下載的新核心
    var updatedBinary: URL { workDir.appendingPathComponent("bin/mihomo") }

    var bundledBinary: URL {
        if let u = Bundle.main.url(forResource: "mihomo", withExtension: nil) { return u }
        // swift run 開發時用專案裡的那份
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("SkyMac/vendor/mihomo")
    }

    /// 一般權限下要用的核心（有更新過就用新的）
    var userBinary: URL {
        FileManager.default.isExecutableFile(atPath: updatedBinary.path) ? updatedBinary : bundledBinary
    }

    private func rootAttrs() -> (owner: Int, perm: Int)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: CoreProcess.rootBinary),
              let owner = a[.ownerAccountID] as? NSNumber, let perm = a[.posixPermissions] as? NSNumber else { return nil }
        return (owner.intValue, perm.intValue)
    }

    /// TUN 背景服務已安裝
    var isDaemonInstalled: Bool {
        guard FileManager.default.fileExists(atPath: CoreProcess.daemonPlist), let a = rootAttrs() else { return false }
        return a.owner == 0 && (a.perm & 0o4000) == 0
    }

    /// 舊版（1.0.x）留下的 setuid 核心，需要升級移除
    var hasLegacySetuid: Bool {
        guard let a = rootAttrs() else { return false }
        return a.owner == 0 && (a.perm & 0o4000) != 0
    }

    /// 核心存放節點來源等資料的資料夾（背景服務模式是 root 的工作資料夾）
    var dataDir: URL { isDaemonInstalled ? URL(fileURLWithPath: CoreProcess.rootWork) : workDir }

    // MARK: - 管理員權限

    static func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    /// 用系統密碼框執行需要管理員權限的指令
    @MainActor
    static func runAsAdmin(_ shell: String, prompt: String) -> (ok: Bool, message: String) {
        let escaped = shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let src = "do shell script \"\(escaped)\" with prompt \"\(prompt)\" with administrator privileges"
        var err: NSDictionary?
        NSAppleScript(source: src)?.executeAndReturnError(&err)
        if let err {
            let code = err[NSAppleScript.errorNumber] as? Int ?? 0
            return (false, code == -128 ? "已取消" : (err[NSAppleScript.errorMessage] as? String ?? "授權失敗"))
        }
        return (true, "")
    }

    /// 背景服務一開機就用的精簡設定：只開控制 API，代理埠等完整設定由 App 推送
    static func bootstrapConfig(controllerPort: Int, secret: String) -> String {
        var y = "# Sky 背景服務的啟動設定；完整設定由 Sky App 透過 API 推送\n"
        y += "external-controller: 127.0.0.1:\(controllerPort)\n"
        y += "secret: " + ConfigBuilder.q(secret) + "\n"
        y += "log-level: warning\n"
        return y
    }

    static var daemonPlistContent: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(daemonLabel)</string>
        <key>ProgramArguments</key><array>
        <string>\(rootBinary)</string><string>-d</string><string>\(rootWork)</string><string>-f</string><string>\(rootWork)/config.yaml</string>
        </array>
        <key>RunAtLoad</key><true/>
        <key>KeepAlive</key><true/>
        <key>ThrottleInterval</key><integer>5</integer>
        <key>StandardOutPath</key><string>\(daemonLog)</string>
        <key>StandardErrorPath</key><string>\(daemonLog)</string>
        </dict></plist>
        """
    }

    /// 安裝（或升級）TUN 背景服務。舊版 setuid 核心會被刪掉並換成一般權限的檔案。
    @MainActor
    func installDaemon(controllerPort: Int, secret: String) -> (ok: Bool, message: String) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("sky-install-\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
            try CoreProcess.bootstrapConfig(controllerPort: controllerPort, secret: secret)
                .write(to: tmp.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
            try CoreProcess.daemonPlistContent.write(to: tmp.appendingPathComponent("daemon.plist"), atomically: true, encoding: .utf8)
        } catch {
            return (false, "準備安裝檔失敗：\(error.localizedDescription)")
        }
        defer { try? fm.removeItem(at: tmp) }
        let q = CoreProcess.shq
        let r = CoreProcess.rootDir, w = CoreProcess.rootWork
        var cmd = "set -e; "
        cmd += "launchctl bootout system/\(CoreProcess.daemonLabel) 2>/dev/null || true; "
        cmd += "rm -f \(q(CoreProcess.rootBinary)); "                         // 舊版 setuid 檔一併刪除
        cmd += "mkdir -p \(q(w)) \(q(CoreProcess.daemonLogDir)); "
        cmd += "cp -f \(q(userBinary.path)) \(q(CoreProcess.rootBinary)); "
        cmd += "cp -f \(q(tmp.appendingPathComponent("config.yaml").path)) \(q(w + "/config.yaml")); "
        for f in ["Country.mmdb", "geoip.dat", "geosite.dat", "ASN.mmdb"] {
            let src = workDir.appendingPathComponent(f).path
            cmd += "if [ -f \(q(src)) ]; then cp -f \(q(src)) \(q(w + "/" + f)); fi; "
        }
        cmd += "cp -f \(q(tmp.appendingPathComponent("daemon.plist").path)) \(q(CoreProcess.daemonPlist)); "
        cmd += "chown -R root:wheel \(q(r)) \(q(CoreProcess.daemonLogDir)) \(q(CoreProcess.daemonPlist)); "
        cmd += "chmod 755 \(q(r)) \(q(w)) \(q(CoreProcess.rootBinary)); "
        cmd += "chmod 600 \(q(w + "/config.yaml")); "
        cmd += "chmod 644 \(q(CoreProcess.daemonPlist)); "
        // 日誌讓 App 可以清空，避免越長越大
        cmd += "touch \(q(CoreProcess.daemonLog)); chmod 666 \(q(CoreProcess.daemonLog)); "
        // 舊版 setuid 核心可能在使用者資料夾留下 root 擁有的檔案，改回使用者
        cmd += "chown -R \(q(NSUserName())):staff \(q(workDir.path)); "
        cmd += "launchctl bootstrap system \(q(CoreProcess.daemonPlist))"
        return CoreProcess.runAsAdmin(cmd, prompt: "Sky 要安裝 TUN 背景服務，讓 mihomo 核心可以建立虛擬網卡")
    }

    /// 換掉背景服務用的核心（更新 mihomo 時）
    @MainActor
    func updateDaemonBinary(from source: URL) -> (ok: Bool, message: String) {
        let q = CoreProcess.shq
        var cmd = "set -e; launchctl bootout system/\(CoreProcess.daemonLabel) 2>/dev/null || true; "
        cmd += "cp -f \(q(source.path)) \(q(CoreProcess.rootBinary)); "
        cmd += "chown root:wheel \(q(CoreProcess.rootBinary)); chmod 755 \(q(CoreProcess.rootBinary)); "
        cmd += "launchctl bootstrap system \(q(CoreProcess.daemonPlist))"
        return CoreProcess.runAsAdmin(cmd, prompt: "Sky 要更新 TUN 背景服務使用的 mihomo 核心")
    }

    /// 移除背景服務（含舊版 setuid 核心），並把 root 寫出的檔案改回使用者
    @MainActor
    func uninstallDaemon() -> (ok: Bool, message: String) {
        let q = CoreProcess.shq
        var cmd = "launchctl bootout system/\(CoreProcess.daemonLabel) 2>/dev/null || true; "
        cmd += "rm -f \(q(CoreProcess.daemonPlist)); rm -rf \(q(CoreProcess.rootDir)) \(q(CoreProcess.daemonLogDir)); "
        cmd += "chown -R \(q(NSUserName())):staff \(q(workDir.path))"
        return CoreProcess.runAsAdmin(cmd, prompt: "Sky 要移除 TUN 背景服務")
    }

    // MARK: - 一般模式的子行程

    var isRunning: Bool { process?.isRunning ?? false }

    /// 用 mihomo -t 檢查設定檔（一律用一般權限的核心，在背景執行緒呼叫）
    func test() -> (ok: Bool, message: String) {
        let p = Process()
        p.executableURL = userBinary
        p.arguments = ["-t", "-d", workDir.path, "-f", configURL.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (false, "無法執行核心：\(error.localizedDescription)") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""
        if p.terminationStatus == 0 { return (true, "") }
        let lines = out.split(separator: "\n").filter { $0.contains("rror") || $0.contains("ERR") || $0.contains("failed") }
        return (false, lines.suffix(3).joined(separator: "\n").ifEmpty(out.suffix(400).description))
    }

    func start() throws {
        stop()
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        let p = Process()
        p.executableURL = userBinary
        p.arguments = ["-d", workDir.path, "-f", configURL.path]
        p.standardOutput = handle
        p.standardError = handle
        try p.run()
        process = p
        try? "\(p.processIdentifier)".write(to: pidURL, atomically: true, encoding: .utf8)
    }

    func stop() {
        guard let p = process else { return }
        if p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(2)
            while p.isRunning && Date() < deadline { usleep(50_000) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        process = nil
        try? FileManager.default.removeItem(at: pidURL)
    }

    /// 上次 App 異常結束時留下的核心
    func killStale() {
        guard let s = try? String(contentsOf: pidURL, encoding: .utf8), let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-p", "\(pid)", "-o", "comm="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        try? ps.run()
        ps.waitUntilExit()
        let comm = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if comm.contains("mihomo") { kill(pid, SIGTERM); usleep(300_000) }
        try? FileManager.default.removeItem(at: pidURL)
    }

    var activeLogURL: URL { isDaemonInstalled ? URL(fileURLWithPath: CoreProcess.daemonLog) : logURL }

    func tailLog(_ n: Int = 200) -> String {
        guard let s = try? String(contentsOf: activeLogURL, encoding: .utf8) else { return "" }
        return s.split(separator: "\n", omittingEmptySubsequences: false).suffix(n).joined(separator: "\n")
    }

    /// 背景服務的日誌超過 10 MB 就清空
    func trimDaemonLog() {
        let path = CoreProcess.daemonLog
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber,
              size.intValue > 10_000_000, let h = FileHandle(forWritingAtPath: path) else { return }
        try? h.truncate(atOffset: 0)
        try? h.close()
    }
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
