import Foundation

// MARK: - 使用者設定（存在 state.json）

struct Subscription: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var url: String
    var enabled = true
    var autoUpdate = true
    var intervalHours = 6
    var viaProxy = true
    var statusOK: Bool?
    var statusMessage: String?
    /// 使用訂閱裡的策略組與規則（完整設定檔才有效）
    var useProfile = true
    /// 「代理」策略要對應到訂閱的哪個策略組（nil = 第一個）
    var mainGroup: String?
    var isProfile = false
    var upload: Int64?
    var download: Int64?
    var total: Int64?
    var expire: Int64?
    var updatedAt: Double?

    var providerName: String { "sub-" + id.uuidString.lowercased() }

    init(name: String, url: String) { self.name = name; self.url = url }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "訂閱"
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? true
        intervalHours = try c.decodeIfPresent(Int.self, forKey: .intervalHours) ?? 6
        viaProxy = try c.decodeIfPresent(Bool.self, forKey: .viaProxy) ?? true
        statusOK = try c.decodeIfPresent(Bool.self, forKey: .statusOK)
        statusMessage = try c.decodeIfPresent(String.self, forKey: .statusMessage)
        useProfile = try c.decodeIfPresent(Bool.self, forKey: .useProfile) ?? true
        mainGroup = try c.decodeIfPresent(String.self, forKey: .mainGroup)
        isProfile = try c.decodeIfPresent(Bool.self, forKey: .isProfile) ?? false
        upload = try c.decodeIfPresent(Int64.self, forKey: .upload)
        download = try c.decodeIfPresent(Int64.self, forKey: .download)
        total = try c.decodeIfPresent(Int64.self, forKey: .total)
        expire = try c.decodeIfPresent(Int64.self, forKey: .expire)
        updatedAt = try c.decodeIfPresent(Double.self, forKey: .updatedAt)
    }
}

enum RulePolicy: String, Codable, CaseIterable, Identifiable {
    case proxy = "代理", direct = "直連", reject = "拒絕", auto = "自動選擇"
    var id: String { rawValue }
    /// 寫進 mihomo 設定檔時的目標名稱
    var target: String {
        switch self {
        case .proxy: return ConfigBuilder.proxyGroup
        case .direct: return "DIRECT"
        case .reject: return "REJECT"
        case .auto: return ConfigBuilder.autoGroup
        }
    }
    var icon: String {
        switch self {
        case .proxy: return "point.3.connected.trianglepath.dotted"
        case .direct: return "arrow.right"
        case .reject: return "nosign"
        case .auto: return "bolt"
        }
    }
}

struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: String
    var payload: String
    var policy: RulePolicy
    var enabled = true

    static let types = ["DOMAIN-SUFFIX", "DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-REGEX",
                        "IP-CIDR", "IP-CIDR6", "SRC-IP-CIDR", "DST-PORT",
                        "PROCESS-NAME", "GEOIP", "GEOSITE"]
}

struct AppSettings: Codable, Equatable {
    var mixedPort = 7899
    var controllerPort = 9099
    var secret = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    var allowLan = false
    var autoConnect = false
    var logLevel = "info"
    var mode = "rule"
    var defaultPolicy: RulePolicy = .proxy
    var testURL = "https://www.gstatic.com/generate_204"
    var tun = false
    var autoCheckUpdates = true
    var lastUpdateCheck: Double = 0
    var ssidEnabled = false
    var ssidRules: [SSIDRule] = []

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        let def = AppSettings()
        mixedPort = try c.decodeIfPresent(Int.self, forKey: .mixedPort) ?? def.mixedPort
        controllerPort = try c.decodeIfPresent(Int.self, forKey: .controllerPort) ?? def.controllerPort
        secret = try c.decodeIfPresent(String.self, forKey: .secret) ?? def.secret
        allowLan = try c.decodeIfPresent(Bool.self, forKey: .allowLan) ?? def.allowLan
        autoConnect = try c.decodeIfPresent(Bool.self, forKey: .autoConnect) ?? def.autoConnect
        logLevel = try c.decodeIfPresent(String.self, forKey: .logLevel) ?? def.logLevel
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? def.mode
        defaultPolicy = try c.decodeIfPresent(RulePolicy.self, forKey: .defaultPolicy) ?? def.defaultPolicy
        testURL = try c.decodeIfPresent(String.self, forKey: .testURL) ?? def.testURL
        tun = try c.decodeIfPresent(Bool.self, forKey: .tun) ?? false
        autoCheckUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? true
        lastUpdateCheck = try c.decodeIfPresent(Double.self, forKey: .lastUpdateCheck) ?? 0
        ssidEnabled = try c.decodeIfPresent(Bool.self, forKey: .ssidEnabled) ?? false
        ssidRules = try c.decodeIfPresent([SSIDRule].self, forKey: .ssidRules) ?? []
    }
}

/// 連到某個 Wi-Fi 時要做什麼
struct SSIDRule: Codable, Identifiable, Equatable {
    var id = UUID()
    var ssid: String
    var action: String = "direct"     // direct / rule / global / disconnect

    static let actions: [(String, String)] = [("direct", "切到直連模式"), ("rule", "切到規則模式"), ("global", "切到全域模式"), ("disconnect", "中斷系統代理")]
}

struct Store: Codable {
    var subscriptions: [Subscription] = []
    var rules: [Rule] = Store.defaultRules
    var settings = AppSettings()
    var localLinks: [String] = []
    var favorites: [String] = []

    static let defaultRules: [Rule] = [
        Rule(type: "DOMAIN-SUFFIX", payload: "local", policy: .direct),
        Rule(type: "IP-CIDR", payload: "127.0.0.0/8", policy: .direct),
        Rule(type: "IP-CIDR", payload: "10.0.0.0/8", policy: .direct),
        Rule(type: "IP-CIDR", payload: "172.16.0.0/12", policy: .direct),
        Rule(type: "IP-CIDR", payload: "192.168.0.0/16", policy: .direct),
        Rule(type: "DOMAIN-SUFFIX", payload: "cn", policy: .direct),
    ]

    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? Store.defaultRules
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        localLinks = try c.decodeIfPresent([String].self, forKey: .localLinks) ?? []
        favorites = try c.decodeIfPresent([String].self, forKey: .favorites) ?? []
    }
}

// MARK: - mihomo API 回傳格式

struct DelayPoint: Decodable, Hashable {
    let time: String
    let delay: Int
}

struct ProxyInfo: Decodable {
    let name: String
    let type: String
    let now: String?
    let all: [String]?
    let history: [DelayPoint]?
    let alive: Bool?

    var lastDelay: Int? { history?.last?.delay }
}

struct SubInfo: Decodable {
    let Upload: Int64?
    let Download: Int64?
    let Total: Int64?
    let Expire: Int64?
}

struct ProviderInfo: Decodable {
    let name: String
    let type: String?
    let vehicleType: String?
    let proxies: [ProxyInfo]?
    let updatedAt: String?
    let subscriptionInfo: SubInfo?

    var isUserProvider: Bool { vehicleType == "HTTP" || vehicleType == "File" }
}

struct ProxiesResp: Decodable { let proxies: [String: ProxyInfo] }
struct ProvidersResp: Decodable { let providers: [String: ProviderInfo] }

struct ConnMeta: Decodable {
    let network: String?
    let type: String?
    let host: String?
    let destinationIP: String?
    let destinationPort: String?
    let process: String?
    let processPath: String?
}

struct Conn: Decodable, Identifiable {
    let id: String
    let metadata: ConnMeta
    let upload: Int64
    let download: Int64
    let start: String?
    let chains: [String]?
    let rule: String?
    let rulePayload: String?

    var destination: String {
        if let h = metadata.host, !h.isEmpty { return h }
        return metadata.destinationIP ?? "—"
    }
    var policyLabel: String {
        let last = chains?.first ?? ""
        if last == "DIRECT" { return "直連" }
        if last == "REJECT" || last == "REJECT-DROP" { return "拒絕" }
        return "代理"
    }
    /// chains 第一個是實際節點，最後一個是策略組
    var nodeName: String { chains?.first ?? "—" }
    var startDate: Date? { start.flatMap(Fmt.parseDate) }
}

struct ConnResp: Decodable {
    let downloadTotal: Int64
    let uploadTotal: Int64
    let connections: [Conn]?
}

struct SpeedSample {
    let date: Date
    let down: Double
    let up: Double
}

/// 節點頁用的整合資料
struct NodeItem: Identifiable {
    var id: String { name }
    let name: String
    let type: String
    let provider: String
    let delay: Int?
    let history: [DelayPoint]
}
