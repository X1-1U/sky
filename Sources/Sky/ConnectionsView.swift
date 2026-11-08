import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject var s: AppState
    @State private var search = ""
    @State private var filter = "all"
    @State private var selectedID: String?

    var filtered: [Conn] {
        s.connections.filter { c in
            (filter == "all" || (filter == "proxy" && c.policyLabel == "代理") || (filter == "direct" && c.policyLabel == "直連"))
            && (search.isEmpty || AppIcons.name(c).localizedCaseInsensitiveContains(search) || c.destination.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        let list = filtered
        let detail = s.connections.first { $0.id == selectedID } ?? list.first

        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                PageTitle(title: "連線")
                StatusPill(text: s.pausedConnections ? "已暫停" : "即時更新", on: !s.pausedConnections)
                Spacer()
                Button { s.pausedConnections.toggle() } label: {
                    Label(s.pausedConnections ? "繼續更新" : "暫停更新", systemImage: s.pausedConnections ? "play.fill" : "pause.fill")
                }
                .buttonStyle(GhostButton())
                Button("中斷全部") { s.closeAllConnections() }
                    .buttonStyle(DangerButton())
                    .disabled(s.connections.isEmpty)
            }

            HStack(spacing: 18) {
                StatCard(icon: "link", title: "活動連線", value: "\(s.activeCount)")
                StatCard(icon: "arrow.down.to.line", title: "下載", value: Fmt.speed(s.downSpeed), iconColor: T.accent)
                StatCard(icon: "arrow.up.to.line", title: "上傳", value: Fmt.speed(s.upSpeed), iconColor: T.accent)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 14) {
                    HStack(spacing: 18) {
                        SearchField(placeholder: "搜尋應用程式或目的地", text: $search)
                        Rectangle().fill(T.line).frame(width: 1, height: 34)
                        Segmented(options: [("all", "全部"), ("proxy", "代理"), ("direct", "直連")], selection: $filter)
                            .frame(width: 290)
                    }
                    TableHeader(columns: [("應用程式", nil), ("目的地", nil), ("策略", 100), ("下載", 110), ("上傳", 90)])
                    if list.isEmpty {
                        Text(s.coreReady ? "目前沒有連線" : "核心尚未啟動")
                            .foregroundColor(T.mute)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(list) { c in row(c, selected: c.id == detail?.id) }
                            }
                        }
                    }
                    Divider().overlay(T.line)
                    HStack {
                        Text("顯示 \(list.count) 筆 · 共 \(s.activeCount) 條活動連線").foregroundColor(T.text.opacity(0.85))
                        Spacer()
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 6)
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(T.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))

                detailPanel(detail)
                    .frame(width: 420)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
    }

    private func policyKind(_ c: Conn) -> TagKind {
        switch c.policyLabel { case "直連": return .gray; case "拒絕": return .red; default: return .solidGreen }
    }

    private func row(_ c: Conn, selected: Bool) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(nsImage: AppIcons.icon(c.metadata.processPath)).resizable().frame(width: 32, height: 32)
                Text(AppIcons.name(c)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(c.destination).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            Tag(text: c.policyLabel, kind: policyKind(c)).frame(width: 100, alignment: .leading)
            Text(Fmt.bytes(c.download)).monospacedDigit().frame(width: 110, alignment: .leading)
            Text(Fmt.bytes(c.upload)).monospacedDigit().frame(width: 90, alignment: .leading)
        }
        .font(.system(size: 17))
        .foregroundColor(T.text)
        .padding(.horizontal, 18)
        .frame(height: 56)
        .background(selected ? T.rowSel : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? T.accent.opacity(0.5) : Color.clear))
        .overlay(alignment: .bottom) { if !selected { Divider().overlay(T.line) } }
        .contentShape(Rectangle())
        .onTapGesture { selectedID = c.id }
    }

    @ViewBuilder
    private func detailPanel(_ c: Conn?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("連線詳情").font(.system(size: 19, weight: .semibold))
            if let c {
                HStack(spacing: 16) {
                    Image(nsImage: AppIcons.icon(c.metadata.processPath)).resizable().frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppIcons.name(c)).font(.system(size: 21, weight: .semibold)).lineLimit(1)
                        Text(AppIcons.bundleID(c)).font(.system(size: 15)).foregroundColor(T.text.opacity(0.75)).lineLimit(1).truncationMode(.middle)
                    }
                }
                Divider().overlay(T.line)
                VStack(spacing: 10) {
                    InfoRow(label: "目的地", value: "\(c.destination):\(c.metadata.destinationPort ?? "")")
                    InfoRow(label: "協定", value: (c.metadata.network ?? "").uppercased())
                    HStack {
                        Text("節點").foregroundColor(T.text.opacity(0.9))
                        Spacer()
                        if c.policyLabel == "代理" { FlagView(name: c.nodeName, size: 18) }
                        Text(Flags.cleanName(c.nodeName)).lineLimit(1)
                    }
                    .font(.system(size: 16))
                    InfoRow(label: "命中規則", value: c.rule.map { r in (c.rulePayload ?? "").isEmpty ? r : "\(r) · \(c.rulePayload!)" } ?? "—")
                    InfoRow(label: "持續時間", value: c.startDate.map { Fmt.duration(Date().timeIntervalSince($0)) } ?? "—")
                }
                Divider().overlay(T.line)
                HStack {
                    Text("傳輸速率").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Legend().font(.system(size: 14))
                }
                let h = s.connHistory[c.id] ?? []
                AreaChart(primary: h.map(\.down), secondary: h.map(\.up),
                          xLabels: AreaChart.timeLabels(h.map(\.date), count: 5, formatter: Fmt.hm),
                          format: AreaChart.speedLabel, ticks: 4, minMax: 64 * 1024, labelWidth: 72, bytesScale: true)
                    .frame(minHeight: 150, maxHeight: 190)
                Spacer(minLength: 0)
                Button { s.closeConnection(c.id); selectedID = nil } label: {
                    Label("中斷此連線", systemImage: "xmark.octagon")
                }
                .buttonStyle(DangerButton(full: true))
            } else {
                Spacer()
                Text("選擇一條連線查看詳情").foregroundColor(T.mute).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .card(20)
    }
}
