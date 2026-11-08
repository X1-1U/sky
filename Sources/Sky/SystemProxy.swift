import Foundation

/// 用 networksetup 設定 macOS 系統代理（一般使用者不需要密碼）
enum SystemProxy {
    static let bypass = ["127.0.0.1", "localhost", "*.local", "10.0.0.0/8", "172.16.0.0/12",
                         "192.168.0.0/16", "169.254.0.0/16", "timestamp.apple.com"]

    @discardableResult
    static func run(_ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let d = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: d, encoding: .utf8) ?? ""
    }

    /// 已啟用的網路服務（Wi-Fi、乙太網路…）
    static func services() -> [String] {
        run(["-listallnetworkservices"])
            .split(separator: "\n")
            .dropFirst()                          // 第一行是說明文字
            .map(String.init)
            .filter { !$0.hasPrefix("*") && !$0.isEmpty }
    }

    static func enable(port: Int) {
        for s in services() {
            run(["-setwebproxy", s, "127.0.0.1", "\(port)"])
            run(["-setsecurewebproxy", s, "127.0.0.1", "\(port)"])
            run(["-setsocksfirewallproxy", s, "127.0.0.1", "\(port)"])
            run(["-setproxybypassdomains", s] + bypass)
        }
    }

    static func disable() {
        for s in services() {
            run(["-setwebproxystate", s, "off"])
            run(["-setsecurewebproxystate", s, "off"])
            run(["-setsocksfirewallproxystate", s, "off"])
        }
    }

    /// 系統代理是否正指向這個埠
    static func isPointing(to port: Int) -> Bool {
        guard let s = services().first else { return false }
        let out = run(["-getwebproxy", s])
        return out.contains("Enabled: Yes") && out.contains("Server: 127.0.0.1") && out.contains("Port: \(port)")
    }
}
