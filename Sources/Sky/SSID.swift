import CoreLocation
import CoreWLAN
import Foundation

/// macOS 14 起讀取 Wi-Fi 名稱需要定位權限
final class LocationAuth: NSObject, CLLocationManagerDelegate {
    static let shared = LocationAuth()
    private let manager = CLLocationManager()
    var onChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var authorized: Bool {
        let s = manager.authorizationStatus
        return s == .authorizedAlways || s == .authorized
    }

    var denied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    func request() { manager.requestWhenInUseAuthorization() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onChange?() }
}

enum WiFi {
    static func ssid() -> String? { CWWiFiClient.shared().interface()?.ssid() }
}

extension AppState {
    func enableSSID(_ on: Bool) {
        store.settings.ssidEnabled = on
        if on {
            LocationAuth.shared.onChange = { [weak self] in Task { @MainActor in await self?.checkSSID(force: true) } }
            if !LocationAuth.shared.authorized { LocationAuth.shared.request() }
            Task { await checkSSID(force: true) }
        } else {
            currentSSID = nil
        }
    }

    /// 定時呼叫：Wi-Fi 換了就套用規則
    func checkSSID(force: Bool = false) async {
        guard store.settings.ssidEnabled else { return }
        let now = WiFi.ssid()
        guard force || now != currentSSID else { return }
        let changed = now != currentSSID
        currentSSID = now
        if changed || force { await applySSID(now) }
    }

    private func applySSID(_ ssid: String?) async {
        if let ssid, let rule = store.settings.ssidRules.first(where: { $0.ssid == ssid }) {
            if ssidSaved == nil { ssidSaved = (store.settings.mode, systemProxyOn) }
            let label = SSIDRule.actions.first { $0.0 == rule.action }?.1 ?? rule.action
            if rule.action == "disconnect" {
                if systemProxyOn { await disconnect() }
            } else if store.settings.mode != rule.action {
                setMode(rule.action)
            }
            showToast("Wi-Fi「\(ssid)」：\(label)")
        } else if let saved = ssidSaved {
            ssidSaved = nil
            if store.settings.mode != saved.mode { setMode(saved.mode) }
            if saved.proxy && !systemProxyOn { await connect() }
            showToast("已離開指定的 Wi-Fi，恢復原本設定")
        }
    }

    func addSSIDRule(_ ssid: String, action: String) {
        let name = ssid.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.settings.ssidRules.removeAll { $0.ssid == name }
        store.settings.ssidRules.append(SSIDRule(ssid: name, action: action))
        Task { await checkSSID(force: true) }
    }

    func removeSSIDRule(_ id: UUID) {
        store.settings.ssidRules.removeAll { $0.id == id }
        Task { await checkSSID(force: true) }
    }
}
