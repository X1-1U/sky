import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var s: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                PageTitle(title: "代理")
                StatusPill(text: s.systemProxyOn ? "已連線" : "未連線", on: s.systemProxyOn)
                if s.tunActive { Tag(text: "TUN", kind: .green, icon: "shield") }
                Spacer()
                Button(s.systemProxyOn ? "中斷連線" : "連線") { s.toggleConnection() }
                    .buttonStyle(PrimaryButton())
                    .disabled(!s.coreReady)
            }

            HStack(spacing: 18) {
                StatCard(icon: "arrow.left.arrow.right", title: "延遲", value: Fmt.delay(s.currentDelay))
                StatCard(icon: "arrow.down.to.line", title: "下載", value: Fmt.speed(s.downSpeed), iconColor: T.accent)
                StatCard(icon: "arrow.up.to.line", title: "上傳", value: Fmt.speed(s.upSpeed), iconColor: T.accent)
                StatCard(icon: "clock", title: "連線時間",
                         value: s.connectedSince.map { Fmt.duration(Date().timeIntervalSince($0)) } ?? "--:--:--")
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("即時流量").font(.system(size: 19, weight: .semibold))
                        Spacer()
                        Legend()
                    }
                    AreaChart(primary: s.history.map(\.down),
                              secondary: s.history.map(\.up),
                              xLabels: AreaChart.timeLabels(s.history.map(\.date), count: 6),
                              format: AreaChart.speedLabel,
                              ticks: 8,
                              minMax: 1024 * 1024, bytesScale: true)
                }
                .frame(maxWidth: .infinity, minHeight: 300, maxHeight: 340)
                .card(20)

                VStack(alignment: .leading, spacing: 16) {
                    Text("當前節點").font(.system(size: 19, weight: .semibold))
                    Button { s.page = .nodes } label: {
                        HStack(spacing: 12) {
                            FlagView(name: s.currentNode ?? "", size: 22)
                            Text(Flags.cleanName(s.currentNode ?? "未選擇")).font(.system(size: 19)).lineLimit(1)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(T.text)
                        }
                        .foregroundColor(T.text)
                        .padding(.horizontal, 18)
                        .frame(height: 62)
                        .background(T.field, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Text("路由模式").font(.system(size: 19, weight: .semibold)).padding(.top, 8)
                    Segmented(options: [("rule", "規則"), ("global", "全域"), ("direct", "直連")],
                              selection: Binding(get: { s.store.settings.mode }, set: { s.setMode($0) }),
                              height: 50)
                    Spacer(minLength: 0)
                }
                .frame(width: 380)
                .frame(minHeight: 300, maxHeight: 340)
                .card(20)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("最近連線").font(.system(size: 19, weight: .semibold))
                TableHeader(columns: [("應用程式", nil), ("目的地", nil), ("策略", 220), ("流量", 140)])
                if s.connections.isEmpty {
                    Text(s.coreReady ? "目前沒有連線" : "核心尚未啟動")
                        .foregroundColor(T.mute).font(.system(size: 15))
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    ForEach(s.connections.prefix(4)) { c in
                        HStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Image(nsImage: AppIcons.icon(c.metadata.processPath)).resizable().frame(width: 30, height: 30)
                                Text(AppIcons.name(c)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(c.destination).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(c.policyLabel == "代理" ? "規則代理" : c.policyLabel).frame(width: 220, alignment: .leading)
                            Text(Fmt.bytes(c.download + c.upload)).monospacedDigit().frame(width: 140, alignment: .leading)
                        }
                        .font(.system(size: 16))
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        Divider().overlay(T.line)
                    }
                }
            }
            .card(20)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
    }
}
