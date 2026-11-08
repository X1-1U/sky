import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var s: AppState
    @State private var mixedPort = ""
    @State private var controllerPort = ""
    @State private var testURL = ""
    @State private var showLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    PageTitle(title: "設定")
                    Subtitle(text: "連接埠、TUN、核心與更新", divider: false)
                    Spacer()
                }

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        section("一般") {
                            toggleRow("開機時自動啟動 Sky", Binding(get: { s.launchAtLogin }, set: { s.setLaunchAtLogin($0) }))
                            Divider().overlay(T.line)
                            toggleRow("啟動後自動連線", Binding(get: { s.store.settings.autoConnect }, set: { s.store.settings.autoConnect = $0 }),
                                      hint: "打開 App 時自動設定系統代理")
                            Divider().overlay(T.line)
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("終端代理命令").font(.system(size: 17))
                                    Text(s.terminalCommand).font(.system(size: 12, design: .monospaced)).foregroundColor(T.mute).lineLimit(2).textSelection(.enabled)
                                }
                                Spacer()
                                Button("複製") { s.copyTerminalCommand() }.buttonStyle(GhostButton(compact: true))
                            }
                        }

                        section("網路") {
                            HStack {
                                Text("混合代理埠（HTTP + SOCKS5）").font(.system(size: 17))
                                Spacer()
                                TextField("7899", text: $mixedPort).skyField().frame(width: 120)
                            }
                            Divider().overlay(T.line)
                            HStack {
                                Text("控制埠（API）").font(.system(size: 17))
                                Spacer()
                                TextField("9099", text: $controllerPort).skyField().frame(width: 120)
                            }
                            Divider().overlay(T.line)
                            toggleRow("允許區域網路連線", Binding(get: { s.store.settings.allowLan }, set: { s.store.settings.allowLan = $0; Task { await s.applyConfig() } }),
                                      hint: "讓同一個網路的手機、電視也能用這台 Mac 的代理")
                            Divider().overlay(T.line)
                            VStack(alignment: .leading, spacing: 8) {
                                Text("延遲測試網址").font(.system(size: 17))
                                TextField("https://www.gstatic.com/generate_204", text: $testURL).skyField()
                            }
                            HStack {
                                Spacer()
                                Button("套用") { applyNetwork() }.buttonStyle(PrimaryButton())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 20) {
                        section("核心") {
                            InfoRow(label: "mihomo 版本", value: s.coreVersion.isEmpty ? "—" : s.coreVersion)
                            Divider().overlay(T.line)
                            HStack {
                                Text("狀態").font(.system(size: 16))
                                Spacer()
                                Tag(text: s.coreReady ? "執行中" : "未執行", kind: s.coreReady ? .green : .red)
                            }
                            Divider().overlay(T.line)
                            HStack {
                                Text("日誌等級").font(.system(size: 17))
                                Spacer()
                                Dropdown(options: [("silent", "安靜"), ("error", "錯誤"), ("warning", "警告"), ("info", "資訊"), ("debug", "除錯")],
                                         selection: Binding(get: { s.store.settings.logLevel }, set: { s.store.settings.logLevel = $0; Task { await s.applyConfig() } }))
                                    .frame(width: 160)
                            }
                            Divider().overlay(T.line)
                            HStack(spacing: 12) {
                                Button("重新啟動核心") { Task { await s.restartCore() } }.buttonStyle(GhostButton(compact: true))
                                Button("查看日誌") { showLog = true }.buttonStyle(GhostButton(compact: true))
                                Button("打開設定資料夾") { NSWorkspace.shared.open(s.workDir) }.buttonStyle(GhostButton(compact: true))
                            }
                        }

                        section("增強模式（TUN）") {
                            toggleRow("TUN 模式", Binding(get: { s.store.settings.tun }, set: { v in Task { await s.setTun(v) } }),
                                      hint: "接管所有程式的流量，包括不理會系統代理的遊戲、終端程式。第一次開啟要輸入一次管理員密碼。")
                            Divider().overlay(T.line)
                            HStack {
                                Text("目前狀態").font(.system(size: 15)).foregroundColor(T.mute)
                                Spacer()
                                if s.tunActive { Tag(text: "已啟用", kind: .green, icon: "shield") }
                                else { Tag(text: "未啟用", kind: .gray) }
                            }
                            HStack {
                                Text(s.core.isTunAuthorized ? "核心已授權" : "核心尚未授權").font(.system(size: 15)).foregroundColor(T.mute)
                                Spacer()
                                if s.core.isTunAuthorized {
                                    Button("移除授權") { Task { await s.revokeTun() } }.buttonStyle(GhostButton(compact: true))
                                }
                            }
                        }

                        section("更新") {
                            InfoRow(label: "Sky 版本", value: "v" + Updater.appVersion)
                            if let u = s.appUpdate {
                                updateRow("有新版 Sky \(u.version)", button: "下載") { s.openAppUpdate() }
                            }
                            Divider().overlay(T.line)
                            InfoRow(label: "mihomo 核心", value: s.coreVersion.isEmpty ? "—" : s.coreVersion)
                            if let u = s.coreUpdate {
                                updateRow("有新版核心 \(u.version)", button: s.coreUpdating ? "更新中…" : "立即更新") { Task { await s.updateCore() } }
                                    .disabled(s.coreUpdating)
                            }
                            Divider().overlay(T.line)
                            toggleRow("每天自動檢查更新", Binding(get: { s.store.settings.autoCheckUpdates }, set: { s.store.settings.autoCheckUpdates = $0 }))
                            Button { Task { await s.checkUpdates(silent: false) } } label: {
                                Label(s.checkingUpdates ? "檢查中…" : "檢查 Sky 與 mihomo 更新", systemImage: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(GhostButton(full: true))
                            .disabled(s.checkingUpdates)
                        }

                        section("關於") {
                            InfoRow(label: "設定資料夾", value: s.workDir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                        }
                    }
                    .frame(width: 460)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 36)
            .padding(.bottom, 24)
        }
        .onAppear {
            mixedPort = "\(s.store.settings.mixedPort)"
            controllerPort = "\(s.store.settings.controllerPort)"
            testURL = s.store.settings.testURL
        }
        .sheet(isPresented: $showLog) { LogSheet(text: s.core.tailLog(400)) }
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 20, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(22)
    }

    private func updateRow(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(text).foregroundColor(T.accent).font(.system(size: 15, weight: .medium))
            Spacer()
            Button(button, action: action).buttonStyle(PrimaryButton())
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(T.pillBG, in: RoundedRectangle(cornerRadius: 9))
    }

    private func toggleRow(_ title: String, _ b: Binding<Bool>, hint: String? = nil) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 17))
                if let hint { Text(hint).font(.system(size: 13)).foregroundColor(T.mute) }
            }
            Spacer()
            SkySwitch(isOn: b, label: title)
        }
    }

    private func applyNetwork() {
        guard let mp = Int(mixedPort), (1...65535).contains(mp), let cp = Int(controllerPort), (1...65535).contains(cp), mp != cp else {
            s.showToast("連接埠要是 1–65535 之間、不重複的數字")
            return
        }
        let controllerChanged = cp != s.store.settings.controllerPort
        let mixedChanged = mp != s.store.settings.mixedPort
        s.store.settings.mixedPort = mp
        s.store.settings.controllerPort = cp
        s.store.settings.testURL = testURL.trimmingCharacters(in: .whitespaces).ifEmpty(AppSettings().testURL)
        Task {
            if controllerChanged { await s.restartCore() } else { await s.applyConfig() }
            if mixedChanged && s.systemProxyOn { await s.connect() }
            s.showToast("已套用")
        }
    }
}

struct LogSheet: View {
    @Environment(\.dismiss) var dismiss
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("核心日誌").font(.system(size: 22, weight: .bold))
                Spacer()
                Button("關閉") { dismiss() }.buttonStyle(GhostButton(compact: true))
            }
            ScrollView {
                Text(text.isEmpty ? "（沒有日誌）" : text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(T.text.opacity(0.9))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(T.bg, in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(24)
        .frame(width: 820, height: 560)
        .background(T.card)
    }
}
