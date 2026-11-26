import Foundation
import Network

/// 只聽 127.0.0.1 的小型檔案伺服器。背景服務模式下，root 核心改從這裡下載
/// 本機節點與其他訂閱，存進它自己的資料夾，不必讀寫使用者資料夾。
/// 網址含隨機 token，而且只開放指定的檔案名稱。
final class LocalFileServer {
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "sky.fileserver")
    private(set) var port: UInt16 = 0
    let token = UUID().uuidString.lowercased()
    /// 名稱 → 檔案；回傳 nil 表示不提供
    var resolver: (String) -> URL? = { _ in nil }

    var baseURL: String? { port == 0 ? nil : "http://127.0.0.1:\(port)/\(token)" }

    func start() {
        guard listener == nil else { return }
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        guard let l = try? NWListener(using: params) else { return }
        let ready = DispatchSemaphore(value: 0)
        l.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.port = l.port?.rawValue ?? 0; ready.signal()
            case .failed: ready.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] c in self?.handle(c) }
        l.start(queue: queue)
        _ = ready.wait(timeout: .now() + 2)
        listener = l
    }

    private func handle(_ c: NWConnection) {
        c.start(queue: queue)
        c.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, _, _ in
            guard let self else { c.cancel(); return }
            let request = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let parts = request.split(separator: "\r\n").first?.split(separator: " ") ?? []
            var status = "404 Not Found"
            var body = Data()
            if parts.count >= 2, parts[0] == "GET" {
                let comps = parts[1].split(separator: "/").map(String.init)
                if comps.count == 2, comps[0] == self.token,
                   comps[1].range(of: "^(sub-[0-9a-f-]{36}|local)$", options: .regularExpression) != nil,
                   let file = self.resolver(comps[1]), let d = try? Data(contentsOf: file) {
                    status = "200 OK"
                    body = d
                }
            }
            var head = "HTTP/1.1 \(status)\r\nContent-Type: text/plain; charset=utf-8\r\n"
            head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            c.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in c.cancel() })
        }
    }
}
