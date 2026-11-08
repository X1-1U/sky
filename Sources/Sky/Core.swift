import Foundation

/// 管理 mihomo 子行程
final class CoreProcess {
    let workDir: URL
    private(set) var process: Process?

    init(workDir: URL) { self.workDir = workDir }

    var configURL: URL { workDir.appendingPathComponent("config.yaml") }
    var logURL: URL { workDir.appendingPathComponent("core.log") }
    private var pidURL: URL { workDir.appendingPathComponent("core.pid") }

    /// TUN 授權後安裝的核心（root 擁有、setuid），可以建立虛擬網卡
    static let privilegedDir = "/Library/Application Support/Sky"
    static let privilegedBinary = URL(fileURLWithPath: privilegedDir + "/mihomo")

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

    var isTunAuthorized: Bool {
        guard let a = try? FileManager.default.attributesOfItem(atPath: CoreProcess.privilegedBinary.path),
              let owner = a[.ownerAccountID] as? NSNumber, let perm = a[.posixPermissions] as? NSNumber else { return false }
        return owner.intValue == 0 && (perm.intValue & 0o4000) != 0
    }

    /// 授權過就一律用 root 版，避免 root 寫出的檔案之後一般權限改不動
    var binary: URL { isTunAuthorized ? CoreProcess.privilegedBinary : userBinary }

    private static func shq(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

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

    /// 把核心安裝成 root 擁有的 setuid 程式
    @MainActor
    func authorizeTun(from source: URL? = nil) -> (ok: Bool, message: String) {
        let src = (source ?? userBinary).path
        let dst = CoreProcess.privilegedBinary.path
        let cmd = "mkdir -p \(CoreProcess.shq(CoreProcess.privilegedDir)) && cp -f \(CoreProcess.shq(src)) \(CoreProcess.shq(dst)) && chown root:wheel \(CoreProcess.shq(dst)) && chmod 4755 \(CoreProcess.shq(dst))"
        return CoreProcess.runAsAdmin(cmd, prompt: "Sky 需要授權 mihomo 核心建立虛擬網卡（TUN 模式）")
    }

    /// 移除授權，並把 root 寫出的檔案改回自己的
    @MainActor
    func revokeTun() -> (ok: Bool, message: String) {
        let cmd = "rm -rf \(CoreProcess.shq(CoreProcess.privilegedDir)) && chown -R \(NSUserName()):staff \(CoreProcess.shq(workDir.path))"
        return CoreProcess.runAsAdmin(cmd, prompt: "Sky 要移除 TUN 模式的授權")
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// 用 mihomo -t 檢查設定檔
    func test() -> (ok: Bool, message: String) {
        let p = Process()
        p.executableURL = binary
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
        p.executableURL = binary
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

    func tailLog(_ n: Int = 200) -> String {
        guard let s = try? String(contentsOf: logURL, encoding: .utf8) else { return "" }
        return s.split(separator: "\n", omittingEmptySubsequences: false).suffix(n).joined(separator: "\n")
    }
}

extension String {
    func ifEmpty(_ other: String) -> String { isEmpty ? other : self }
}
