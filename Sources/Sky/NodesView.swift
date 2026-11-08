import SwiftUI

struct NodesView: View {
    @EnvironmentObject var s: AppState
    @State private var search = ""
    @State private var filter = 0            // 0 全部 1 收藏 2 低延遲
    @State private var groupSel: String?
    @State private var selected: String?
    @State private var sortByDelay = false
    @State private var showAdd = false
    @State private var editingLink: EditLink?

    struct EditLink: Identifiable { let id = UUID(); let index: Int; var text: String }

    /// 目前在看的策略組（預設主要策略組）
    var group: String { groupSel.flatMap { s.groups.contains($0) ? $0 : nil } ?? s.mainGroup }
    var groupNow: String? { s.proxies[group]?.now }
    var canSelect: Bool { s.proxies[group]?.type == "Selector" }

    var filtered: [NodeItem] {
        var list = s.members(of: group)
        if filter == 1 { list = list.filter { s.store.favorites.contains($0.name) } }
        if filter == 2 { list = list.filter { ($0.delay ?? 0) > 0 && ($0.delay ?? 0) < 150 } }
        if !search.isEmpty { list = list.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.type.localizedCaseInsensitiveContains(search) } }
        if sortByDelay {
            list.sort { a, b in
                let x = (a.delay ?? 0) == 0 ? Int.max : a.delay!
                let y = (b.delay ?? 0) == 0 ? Int.max : b.delay!
                return x < y
            }
        }
        return list
    }

    var body: some View {
        let all = s.members(of: group)
        let list = filtered
        let detailName = selected ?? groupNow
        let detail = all.first { $0.name == detailName } ?? list.first

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 18) {
                        PageTitle(title: "節點")
                        StatusPill(text: s.systemProxyOn ? "已連線" : "未連線", on: s.systemProxyOn)
                    }
                    Text(s.profileSub.map { "使用訂閱「\($0.name)」的策略組" } ?? "選擇連線節點").font(.system(size: 17)).foregroundColor(T.text.opacity(0.8))
                }
                Spacer()
                Button { s.testGroup(group) } label: {
                    Label(s.testingDelay ? "測試中…" : "測試延遲", systemImage: "gauge.with.dots.needle.33percent")
                }
                .buttonStyle(GhostButton())
                .disabled(s.testingDelay || !s.coreReady)
                Button { showAdd = true } label: { Label("新增節點", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
            }

            HStack(spacing: 14) {
                SearchField(placeholder: "搜尋節點", text: $search).frame(minWidth: 160, maxWidth: 340)
                Chip(title: "全部", selected: filter == 0) { filter = 0 }
                Chip(title: "收藏", selected: filter == 1) { filter = 1 }
                Chip(title: "低延遲", selected: filter == 2) { filter = 2 }
                Spacer(minLength: 0)
                Rectangle().fill(T.line).frame(width: 1, height: 36)
                Dropdown(options: s.groups.map { g in (g, groupLabel(g)) },
                         selection: Binding(get: { group }, set: { groupSel = $0; selected = nil }))
                    .frame(minWidth: 180, maxWidth: 380)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        Color.clear.frame(width: 96)
                        Text("節點名稱").frame(maxWidth: .infinity, alignment: .leading)
                        Text("協定").frame(width: 130, alignment: .leading)
                        Button { sortByDelay.toggle() } label: {
                            HStack(spacing: 6) {
                                Text("延遲")
                                Image(systemName: sortByDelay ? "arrow.up" : "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(width: 90, alignment: .leading)
                        Text("狀態").frame(width: 100, alignment: .leading)
                        Color.clear.frame(width: 40)
                    }
                    .font(.system(size: 16, weight: .medium))
                    .padding(.horizontal, 6)
                    .frame(height: 64)

                    if all.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray").font(.system(size: 34)).foregroundColor(T.mute)
                            Text(s.coreReady ? "還沒有節點，先到「訂閱」新增訂閱連結，或按「新增節點」貼上分享連結" : "核心尚未啟動")
                                .foregroundColor(T.mute).multilineTextAlignment(.center)
                            if s.coreReady {
                                Button("前往訂閱") { s.page = .subscriptions }.buttonStyle(GhostButton(compact: true))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(list) { n in row(n, isDetail: n.name == detail?.name) }
                            }
                        }
                    }
                    Divider().overlay(T.line)
                    HStack {
                        Text("共 \(all.count) 個節點 · \(list.count) 個已顯示").foregroundColor(T.text.opacity(0.85))
                        Spacer()
                    }
                    .font(.system(size: 15))
                    .padding(.horizontal, 18)
                    .frame(height: 50)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(T.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))

                detailPanel(detail)
                    .frame(width: 370)
                    .frame(maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 24)
        .sheet(isPresented: $showAdd) { AddLinksSheet { s.addLocalLinks($0) } }
        .sheet(item: $editingLink) { e in
            EditLinkSheet(text: e.text) { new in
                guard e.index < s.store.localLinks.count else { return }
                if new.trimmingCharacters(in: .whitespaces).isEmpty {
                    s.store.localLinks.remove(at: e.index)
                } else {
                    s.store.localLinks[e.index] = new.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                Task { await s.applyConfig() }
            }
        }
    }

    private func groupLabel(_ g: String) -> String {
        let now = s.proxies[g]?.now.map { " · " + Flags.cleanName($0) } ?? ""
        return (g == s.mainGroup ? "★ " : "") + g + now
    }

    private func status(_ n: NodeItem) -> (String, TagKind) {
        if n.name == groupNow { return ("使用中", .solidGreen) }
        if s.isGroup(n.name) { return ("策略組", .gray) }
        if n.name == "DIRECT" || n.name == "REJECT" { return ("內建", .gray) }
        guard let d = n.delay else { return ("未測試", .gray) }
        return d == 0 ? ("逾時", .red) : ("可用", .green)
    }

    @ViewBuilder
    private func row(_ n: NodeItem, isDetail: Bool) -> some View {
        let fav = s.store.favorites.contains(n.name)
        let st = status(n)
        HStack(spacing: 0) {
            Button { s.toggleFavorite(n.name) } label: {
                Image(systemName: fav ? "star.fill" : "star")
                    .font(.system(size: 19))
                    .foregroundColor(fav ? T.accent : T.text.opacity(0.85))
            }
            .buttonStyle(.plain)
            .frame(width: 46)
            FlagView(name: n.name, size: 24).frame(width: 50)
            Text(Flags.cleanName(n.name)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text(n.type).lineLimit(1).frame(width: 130, alignment: .leading)
            Text(n.delay == nil ? "—" : Fmt.delay(n.delay)).monospacedDigit().frame(width: 90, alignment: .leading)
            Tag(text: st.0, kind: st.1).frame(width: 100, alignment: .leading)
            Menu {
                if canSelect { Button("使用此節點") { s.select(n.name, in: group) } }
                Button("測試延遲") { s.testDelay(n.name) }
                Button(fav ? "取消收藏" : "加入收藏") { s.toggleFavorite(n.name) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).foregroundColor(T.text)
                    .frame(width: 40, height: 40).contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .frame(width: 40)
        }
        .font(.system(size: 17))
        .foregroundColor(T.text)
        .padding(.horizontal, 6)
        .frame(height: 62)
        .background(isDetail ? T.rowSel : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(isDetail ? T.accent.opacity(0.5) : Color.clear))
        .overlay(alignment: .bottom) { if !isDetail { Divider().overlay(T.line).padding(.horizontal, 14) } }
        .contentShape(Rectangle())
        .onTapGesture { selected = n.name }
        .onTapGesture(count: 2) { if canSelect { s.select(n.name, in: group) } }
    }

    @ViewBuilder
    private func detailPanel(_ n: NodeItem?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let n {
                let inUse = n.name == groupNow
                let fav = s.store.favorites.contains(n.name)
                HStack(alignment: .top) {
                    FlagView(name: n.name, size: 28)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Flags.cleanName(n.name)).font(.system(size: 26, weight: .medium)).lineLimit(2)
                        if inUse {
                            Tag(text: "使用中", kind: .green)
                        } else if canSelect {
                            Button("使用此節點") { s.select(n.name, in: group) }.buttonStyle(GhostButton(compact: true))
                        } else {
                            Tag(text: "此策略組自動選擇", kind: .gray)
                        }
                    }
                    Spacer()
                    Button { s.toggleFavorite(n.name) } label: {
                        Image(systemName: fav ? "star.fill" : "star").font(.system(size: 22)).foregroundColor(T.accent)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("延遲（最近測試）").font(.system(size: 16, weight: .medium))
                        Spacer()
                        Text("當前：\(Fmt.delay(n.delay))").font(.system(size: 16)).monospacedDigit()
                    }
                    let pts = n.history.filter { $0.delay > 0 }
                    if pts.count >= 2 {
                        AreaChart(primary: pts.map { Double($0.delay) },
                                  xLabels: AreaChart.timeLabels(pts.compactMap { Fmt.parseDate($0.time) }, count: min(5, pts.count), formatter: Fmt.hm),
                                  format: { "\(Int($0)) ms" },
                                  ticks: 4, minMax: 20, labelWidth: 56)
                            .frame(height: 140)
                    } else {
                        Text(n.history.isEmpty ? "還沒有測試紀錄，按「測試延遲」開始" : (pts.isEmpty ? "最近的測試都逾時，這個節點可能無法連線" : "再測試一次就能看到變化"))
                            .font(.system(size: 14)).foregroundColor(T.mute)
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(16)
                .background(T.bg.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))

                let addr = s.detailFile(for: n).flatMap { NodeDetails.lookup(name: n.name, file: $0) }
                VStack(spacing: 0) {
                    Button { s.page = .subscriptions } label: {
                        HStack {
                            Text("所屬訂閱")
                            Spacer()
                            Text(s.providerDisplayName(n.provider))
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        }
                        .font(.system(size: 16)).foregroundColor(T.text)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(height: 46)
                    Divider().overlay(T.line)
                    InfoRow(label: "協定", value: n.type).frame(height: 46)
                    Divider().overlay(T.line)
                    InfoRow(label: "伺服器", value: addr?.server ?? "—").frame(height: 46)
                    Divider().overlay(T.line)
                    InfoRow(label: "連接埠", value: addr?.port ?? "—").frame(height: 46)
                    Divider().overlay(T.line)
                }
                Spacer(minLength: 0)
                if n.provider == ConfigBuilder.localProvider {
                    Button { openEditor(n) } label: { Label("編輯節點", systemImage: "pencil") }
                        .buttonStyle(GhostButton(full: true))
                } else {
                    Button { s.testDelay(n.name) } label: { Label("測試這個節點", systemImage: "gauge.with.dots.needle.33percent") }
                        .buttonStyle(GhostButton(full: true))
                }
            } else {
                Spacer()
                Text("選擇一個節點查看詳情").foregroundColor(T.mute).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .card(22)
    }

    private func openEditor(_ n: NodeItem) {
        // 在本機連結中找到名稱符合的那一條
        let idx = s.store.localLinks.firstIndex { link in
            if let hash = link.lastIndex(of: "#") {
                return String(link[link.index(after: hash)...]).removingPercentEncoding == n.name
            }
            if link.hasPrefix("vmess://"), let d = Data(base64Encoded: String(link.dropFirst(8)).padBase64()),
               let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                return j["ps"] as? String == n.name
            }
            return false
        }
        if let idx { editingLink = EditLink(index: idx, text: s.store.localLinks[idx]) }
        else { s.showToast("找不到這個節點的原始連結") }
    }
}

struct AddLinksSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    let onAdd: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增節點").font(.system(size: 22, weight: .bold))
            Text("貼上節點分享連結，一行一個。支援 ss://、vmess://、vless://、trojan://、hysteria2://、tuic:// 等。")
                .font(.system(size: 14)).foregroundColor(T.mute)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(T.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line))
                .frame(height: 200)
            HStack {
                Button("從剪貼簿貼上") { text = NSPasteboard.general.string(forType: .string) ?? "" }.buttonStyle(GhostButton(compact: true))
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(GhostButton(compact: true))
                Button("新增") { onAdd(text); dismiss() }.buttonStyle(PrimaryButton())
                    .disabled(!text.contains("://"))
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(T.card)
    }
}

struct EditLinkSheet: View {
    @Environment(\.dismiss) var dismiss
    @State var text: String
    let onSave: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("編輯節點").font(.system(size: 22, weight: .bold))
            Text("修改分享連結；清空後儲存會刪除這個節點。").font(.system(size: 14)).foregroundColor(T.mute)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(T.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line))
                .frame(height: 140)
            HStack {
                Button("刪除節點") { onSave(""); dismiss() }.buttonStyle(DangerButton())
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(GhostButton(compact: true))
                Button("儲存") { onSave(text); dismiss() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(T.card)
    }
}
