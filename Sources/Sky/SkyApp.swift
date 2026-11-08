import AppKit
import SwiftUI

@main
struct SkyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        Window("Sky", id: "main") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1200, minHeight: 780)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1320, height: 860)

        MenuBarExtra {
            MenuPanel()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: state.systemProxyOn ? "paperplane.fill" : "paperplane")
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in await AppState.shared.bootstrap() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { AppState.shared.shutdown() }
    }
}

struct RootView: View {
    @EnvironmentObject var s: AppState
    @State private var updateDismissed = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ZStack(alignment: .bottom) {
                Group {
                    switch s.page {
                    case .overview: OverviewView()
                    case .nodes: NodesView()
                    case .subscriptions: SubscriptionsView()
                    case .rules: RulesView()
                    case .connections: ConnectionsView()
                    case .settings: SettingsView()
                    }
                }
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()

                if let e = s.coreError {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(T.amber)
                        Text(e).font(.system(size: 13)).foregroundColor(T.text).lineLimit(3).textSelection(.enabled)
                        Spacer()
                        Button("重新啟動核心") { Task { await s.restartCore() } }.buttonStyle(GhostButton(compact: true))
                    }
                    .padding(14)
                    .background(Color(hex: 0x3A2E14), in: RoundedRectangle(cornerRadius: 10))
                    .padding(20)
                }
                if (s.appUpdate != nil || s.coreUpdate != nil) && !updateDismissed && s.page != .settings {
                    VStack {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.circle.fill").foregroundColor(T.accent)
                            Text(s.appUpdate.map { "Sky 有新版本 \($0.version)" } ?? "mihomo 核心有新版本 \(s.coreUpdate?.version ?? "")")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Button("查看") { s.page = .settings }.buttonStyle(PrimaryButton())
                            Button { updateDismissed = true } label: { Image(systemName: "xmark").foregroundColor(T.text) }
                                .buttonStyle(.plain).accessibilityLabel("關閉")
                        }
                        .padding(14)
                        .frame(width: 440)
                        .background(Color(hex: 0x173A31), in: RoundedRectangle(cornerRadius: 10))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 20).padding(.trailing, 32)
                        Spacer()
                    }
                }
                if let t = s.toast {
                    Text(t)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(T.text)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color(hex: 0x2C2F36), in: Capsule())
                        .overlay(Capsule().stroke(T.line))
                        .padding(.bottom, s.coreError == nil ? 24 : 110)
                        .transition(.opacity)
                }
            }
        }
        .background(T.bg)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.2), value: s.toast)
    }
}

struct Sidebar: View {
    @EnvironmentObject var s: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Page.allCases) { p in
                Button { s.page = p } label: {
                    HStack(spacing: 16) {
                        Image(systemName: p.icon).font(.system(size: 18)).frame(width: 26)
                        Text(p.title).font(.system(size: 17, weight: .medium))
                    }
                    .foregroundColor(T.text)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(s.page == p ? T.accentDim : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            HStack(spacing: 8) {
                Circle().fill(s.coreReady ? T.accent : T.red).frame(width: 8, height: 8)
                Text(s.coreReady ? "mihomo \(s.coreVersion)" : "核心未執行")
                    .font(.system(size: 12)).foregroundColor(T.mute).lineLimit(1)
            }
            .padding(.horizontal, 16).padding(.bottom, 18)
        }
        .padding(.top, 64)
        .padding(.horizontal, 10)
        .frame(width: 216)
        .frame(maxHeight: .infinity)
        .background(T.sidebar)
    }
}
