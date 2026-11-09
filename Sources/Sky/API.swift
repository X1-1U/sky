import Foundation

struct APIError: LocalizedError {
    let status: Int
    let body: String
    var errorDescription: String? { "HTTP \(status) \(body)" }
}

/// mihomo external-controller REST API
struct MihomoAPI {
    let port: Int
    let secret: String

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.connectionProxyDictionary = [:]   // 不要走系統代理（就是自己）
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    @discardableResult
    func request(_ path: String, method: String = "GET", query: [String: String] = [:], body: Any? = nil, timeout: TimeInterval = 10) async throws -> Data {
        var s = "http://127.0.0.1:\(port)\(path)"
        if !query.isEmpty {
            s += "?" + query.map { "\($0.key)=\(MihomoAPI.enc($0.value))" }.joined(separator: "&")
        }
        guard let url = URL(string: s) else { throw APIError(status: 0, body: "bad url") }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = method
        r.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        if let body {
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await MihomoAPI.session.data(for: r)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw APIError(status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    func version() async throws -> String {
        let d = try await request("/version", timeout: 1)
        let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any]
        return obj?["version"] as? String ?? "?"
    }

    func proxies() async throws -> [String: ProxyInfo] {
        try JSONDecoder().decode(ProxiesResp.self, from: try await request("/proxies")).proxies
    }

    func providers() async throws -> [String: ProviderInfo] {
        try JSONDecoder().decode(ProvidersResp.self, from: try await request("/providers/proxies")).providers
    }

    func connections() async throws -> ConnResp {
        try JSONDecoder().decode(ConnResp.self, from: try await request("/connections", timeout: 3))
    }

    func select(group: String, name: String) async throws {
        try await request("/proxies/\(MihomoAPI.enc(group))", method: "PUT", body: ["name": name])
    }

    /// 回傳毫秒；逾時或失敗回傳 0
    /// 節點來源裡的節點要用 /providers/proxies/{來源}/{節點}/healthcheck，/proxies/{節點}/delay 會 404
    func delay(_ name: String, provider: String? = nil, url: String, timeout: Int = 5000) async -> Int {
        let path = provider.map { "/providers/proxies/\(MihomoAPI.enc($0))/\(MihomoAPI.enc(name))/healthcheck" } ?? "/proxies/\(MihomoAPI.enc(name))/delay"
        guard let d = try? await request(path, query: ["url": url, "timeout": "\(timeout)"], timeout: Double(timeout) / 1000 + 3),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return 0 }
        return obj["delay"] as? Int ?? 0
    }

    func groupDelay(_ group: String, url: String, timeout: Int = 5000) async throws -> [String: Int] {
        let d = try await request("/group/\(MihomoAPI.enc(group))/delay", query: ["url": url, "timeout": "\(timeout)"], timeout: 30)
        return (try JSONSerialization.jsonObject(with: d) as? [String: Int]) ?? [:]
    }

    func updateProvider(_ name: String) async throws {
        try await request("/providers/proxies/\(MihomoAPI.enc(name))", method: "PUT", timeout: 60)
    }

    func healthcheck(_ provider: String) async throws {
        try await request("/providers/proxies/\(MihomoAPI.enc(provider))/healthcheck", timeout: 60)
    }

    func setMode(_ mode: String) async throws {
        try await request("/configs", method: "PATCH", body: ["mode": mode])
    }

    func reload(path: String) async throws {
        try await request("/configs", method: "PUT", query: ["force": "true"], body: ["path": path], timeout: 60)
    }

    func closeConnection(_ id: String) async throws {
        try await request("/connections/\(MihomoAPI.enc(id))", method: "DELETE")
    }

    func closeAll() async throws {
        try await request("/connections", method: "DELETE")
    }
}
