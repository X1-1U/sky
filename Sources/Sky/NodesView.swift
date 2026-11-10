import SwiftUI

/// 節點頁（參考 Clash Verge）：所有策略組由上往下排列，點標題展開，節點以卡片格狀顯示，點卡片直接切換
struct NodesView: View {
    @EnvironmentObject var s: AppState
    @State private var search = ""
    @State private var filter = 0                 // 0 全部 1 收藏 2 低延遲
    @State private var expanded: Set<String> = []
    @State private var didInit = false
    @State private var sortByDelay = false
    @State private var showAdd = false
    @State private var editingLink: EditLink?
    @State private var testing: Set<String> = []

    struct EditLink: Identifiable { let id = UUID(); let index: Int; var text: String }

    static func typeLabel(_ t: String?) -> String {
        switch t {
        case "Selector": return "手動選擇"
        case "URLTest": return "自動測速"
        case "Fallback": return "故障轉移"
        case "LoadBalance": return "負載均衡"
        case "Relay": return "鏈式代理"
        default: return t ?? ""
        }
    }

    private func items(_ g: String) -> [NodeItem] {
        var list = s.members(of: g)
        if filter == 1 { list = list.filter { s.store.favorites.contains($0.name) || s.isGroup($0.name) } }
        if filter == 2 { list = list.filter { s.isGroup($0.name) || (($0.delay ?? 0) > 0 && ($0.delay ?? 0) < 150) } }
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
        let groups = s.groups
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 18) {
                        PageTitle(title: "節點")
                        StatusPill(text: s.connectionLabel, on: s.isConnected)
                    }
                    Text(s.profileSub.map { "使用訂閱「\($0.name)」的 \(groups.count) 個策略組" } ?? "選擇連線節點")
                        .font(.system(size: 17)).foregroundColor(T.text.opacity(0.8))
                }
                Spacer()
                Button { expanded = expanded.count == groups.count ? [] : Set(groups) } label: {
                    Label(expanded.count == groups.count && !groups.isEmpty ? "全部收合" : "全部展開", systemImage: "rectangle.expand.vertical")
                }
                .buttonStyle(GhostButton())
                Button { showAdd = true } label: { Label("新增節點", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
            }

            HStack(spacing: 12) {
                SearchField(placeholder: "搜尋節點", text: $search).frame(minWidth: 160, maxWidth: 340)
                Chip(title: "全部", selected: filter == 0) { filter = 0 }
                Chip(title: "收藏", selected: filter == 1) { filter = 1 }
                Chip(title: "低延遲", selected: filter == 2) { filter = 2 }
                Spacer(minLength: 0)
                Button { sortByDelay.toggle() } label: {
                    Label(sortByDelay ? "依延遲排序" : "原始順序", systemImage: sortByDelay ? "arrow.up.arrow.down.circle.fill" : "arrow.up.arrow.down.circle")
                }
                .buttonStyle(GhostButton(compact: true))
            }

            if groups.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray").font(.system(size: 34)).foregroundColor(T.mute)
                    Text(s.coreReady ? "還沒有節點，先到「訂閱」新增訂閱連結，或按「新增節點」貼上分享連結" : "核心尚未啟動")
                        .foregroundColor(T.mute).multilineTextAlignment(.center)
                    if s.coreReady { Button("前往訂閱") { s.page = .subscriptions }.buttonStyle(GhostButton(compact: true)) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(groups, id: \.self) { g in
                                groupSection(g).id(g)
                            }
                        }
                        .padding(.bottom, 12)
                    }
                    .onAppear {
                        guard !didInit else { return }
                        didInit = true
                        expanded = [s.mainGroup]
                        if let target = ProcessInfo.processInfo.environment["SKY_EXPAND"] { expanded.insert(target); proxy.scrollTo(target, anchor: .top) }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 20)
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

    // MARK: 一個策略組

    @ViewBuilder
    private func groupSection(_ g: String) -> some View {
        let open = expanded.contains(g)
        let info = s.proxies[g]
        let now = info?.now
        let final = s.resolve(g)
        let selectable = info?.type == "Selector"
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(T.mute)
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(g).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        Tag(text: NodesView.typeLabel(info?.type), kind: selectable ? .green : .gray).fixedSize()
                        if g == s.mainGroup { Tag(text: "「代理」", kind: .gray).fixedSize().help("規則頁中策略選「代理」的規則走這個策略組") }
                    }
                    HStack(spacing: 6) {
                        if let now {
                            Text(Flags.cleanName(now)).lineLimit(1)
                            if let final, final != now {
                                Image(systemName: "arrow.right").font(.system(size: 10))
                                FlagView(name: final, size: 12)
                                Text(Flags.cleanName(final)).lineLimit(1)
                            }
                        }
                    }
                    .font(.system(size: 13)).foregroundColor(T.text.opacity(0.7))
                }
                Spacer()
                if let final, let d = s.proxies[final]?.lastDelay {
                    Text(Fmt.delay(d)).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundColor(delayColor(d))
                }
                Text("\(info?.all?.count ?? 0)").font(.system(size: 13)).foregroundColor(T.mute)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(T.field, in: Capsule())
                Button { testGroup(g) } label: {
                    if testing.contains(g) { ProgressView().controlSize(.small).frame(width: 20) }
                    else { Image(systemName: "gauge.with.dots.needle.33percent").font(.system(size: 17)).foregroundColor(T.text) }
                }
                .buttonStyle(.plain).help("測試這組的延遲").disabled(testing.contains(g))
            }
            .padding(.horizontal, 16)
            .frame(height: 66)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) {
                    if open { expanded.remove(g) } else { expanded.insert(g) }
                }
            }

            if open {
                let list = items(g)
                Divider().overlay(T.line)
                if list.isEmpty {
                    Text("沒有符合的節點").font(.system(size: 14)).foregroundColor(T.mute).frame(maxWidth: .infinity).padding(20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 215), spacing: 10)], spacing: 10) {
                        ForEach(list) { n in nodeCard(n, group: g, selected: n.name == now, selectable: selectable) }
                    }
                    .padding(14)
                }
            }
        }
        .background(T.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
    }

    private func testGroup(_ g: String) {
        testing.insert(g)
        Task {
            _ = try? await s.api.groupDelay(g, url: s.store.settings.testURL)
            await s.refreshProxies()
            testing.remove(g)
        }
    }

    private func delayColor(_ d: Int) -> Color {
        d == 0 ? T.red : (d < 200 ? T.accent : (d < 500 ? T.amber : Color(hex: 0xFB923C)))
    }

    // MARK: 節點卡片

    private func nodeCard(_ n: NodeItem, group: String, selected: Bool, selectable: Bool) -> some View {
        let sub = s.isGroup(n.name)
        let fav = s.store.favorites.contains(n.name)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if sub { Image(systemName: "folder.fill").font(.system(size: 13)).foregroundColor(T.accent) }
                else { FlagView(name: n.name, size: 15) }
                Text(Flags.cleanName(n.name)).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                if fav { Image(systemName: "star.fill").font(.system(size: 10)).foregroundColor(T.accent) }
            }
            HStack(spacing: 6) {
                Text(sub ? NodesView.typeLabel(n.type) : n.type).font(.system(size: 12)).foregroundColor(T.mute).lineLimit(1)
                if sub, let r = s.resolve(n.name) {
                    Text("→ \(Flags.cleanName(r))").font(.system(size: 12)).foregroundColor(T.mute).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !sub {
                    Button { s.testDelay(n.name) } label: {
                        Text(n.delay == nil ? "測速" : Fmt.delay(n.delay))
                            .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                            .foregroundColor(n.delay.map(delayColor) ?? T.mute)
                    }
                    .buttonStyle(.plain).help("測試這個節點")
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(selected ? T.rowSel : T.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected ? T.accent : T.line, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture {
            if selectable && !selected { s.select(n.name, in: group) }
            else if sub { withAnimation { _ = expanded.insert(n.name) } }
        }
        .help(sub ? "子策略組「\(n.name)」" : n.name)
        .contextMenu {
            if selectable { Button("使用這個") { s.select(n.name, in: group) } }
            if sub { Button("展開「\(n.name)」") { expanded.insert(n.name) } }
            if !sub { Button("測試延遲") { s.testDelay(n.name) } }
            Button(fav ? "取消收藏" : "加入收藏") { s.toggleFavorite(n.name) }
            if !sub {
                Button("複製伺服器位址") {
                    // 要用時才去訂閱檔裡找，不在每次重畫時讀檔
                    if let a = s.detailFile(for: n).flatMap({ NodeDetails.lookup(name: n.name, file: $0) }) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("\(a.server):\(a.port)", forType: .string)
                        s.showToast("已複製 \(a.server):\(a.port)")
                    } else { s.showToast("找不到這個節點的伺服器位址") }
                }
            }
            if isLocal(n) { Button("編輯節點") { openEditor(n) } }
        }
    }

    private func isLocal(_ n: NodeItem) -> Bool { n.provider == ConfigBuilder.localProvider }

    private func openEditor(_ n: NodeItem) {
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
