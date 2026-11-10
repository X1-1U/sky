import SwiftUI

/// 點選單列圖示跳出的面板
struct MenuPanel: View {
    @EnvironmentObject var s: AppState
    @EnvironmentObject var live: LiveStats
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9).fill(T.accent).frame(width: 36, height: 36)
                    Image(systemName: "paperplane.fill").font(.system(size: 17, weight: .semibold)).foregroundColor(T.accentInk)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sky").font(.system(size: 16, weight: .semibold))
                    Text(!s.coreReady ? "核心未執行" : s.connectionLabel)
                        .font(.system(size: 12)).foregroundColor(T.mute)
                }
                Spacer()
                SkySwitch(isOn: Binding(get: { s.isConnected }, set: { _ in s.toggleConnection() }), label: "系統代理")
                    .disabled(!s.coreReady)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("目前節點").font(.system(size: 12)).foregroundColor(T.mute)
                    Spacer()
                    Text(Fmt.delay(s.currentDelay)).font(.system(size: 12, weight: .semibold)).foregroundColor(T.accent)
                }
                Menu {
                    if let g = s.proxies[s.mainGroup] {
                        ForEach(g.all ?? [], id: \.self) { n in
                            Button { s.select(n, in: s.mainGroup) } label: {
                                if n == g.now { Label(n, systemImage: "checkmark") } else { Text(n) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        FlagView(name: s.currentNode ?? "", size: 16)
                        Text(Flags.cleanName(s.currentNode ?? "未選擇")).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if let now = s.currentGroupNow, s.isGroup(now) {
                            Text(now).font(.system(size: 11)).foregroundColor(T.accent).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11)).foregroundColor(T.mute)
                    }
                    .foregroundColor(T.text)
                    .contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                HStack {
                    Label(Fmt.speed(live.upSpeed), systemImage: "arrow.up").foregroundColor(Color(hex: 0x7DD3FC))
                    Spacer()
                    Label(Fmt.speed(live.downSpeed), systemImage: "arrow.down").foregroundColor(T.accent)
                    Spacer()
                }
                .font(.system(size: 13).monospacedDigit())
            }
            .padding(12)
            .background(T.field, in: RoundedRectangle(cornerRadius: 10))

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TUN 模式").font(.system(size: 13))
                    Text(s.tunActive ? "已接管所有程式的流量" : "接管所有程式的流量").font(.system(size: 11)).foregroundColor(T.mute)
                }
                Spacer()
                SkySwitch(isOn: Binding(get: { s.store.settings.tun }, set: { v in Task { await s.setTun(v) } }), label: "TUN 模式")
                    .disabled(!s.coreReady || s.busy)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("路由模式").font(.system(size: 12)).foregroundColor(T.mute)
                Segmented(options: [("rule", "規則"), ("global", "全域"), ("direct", "直連")],
                          selection: Binding(get: { s.store.settings.mode }, set: { s.setMode($0) }),
                          height: 34)
            }

            Divider().overlay(T.line)
            VStack(spacing: 0) {
                menuButton("打開主視窗", "⌘O") {
                    if s.openMainWindow == nil { let o = openWindow; s.openMainWindow = { o(id: "main") } }
                    s.showMainWindow()
                }
                .keyboardShortcut("o")
                menuButton("複製終端代理命令", "⌘C") { s.copyTerminalCommand() }
                    .keyboardShortcut("c")
                menuButton("結束 Sky", "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(T.sidebar)
    }

    private func menuButton(_ title: String, _ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                Text(key).font(.system(size: 12)).foregroundColor(T.mute)
            }
            .foregroundColor(T.text)
            .padding(.horizontal, 4)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
