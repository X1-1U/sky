import SwiftUI

struct SubscriptionsView: View {
    @EnvironmentObject var s: AppState
    @State private var selectedID: UUID?
    @State private var draft: Subscription?
    @State private var showURL = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 20) {
                PageTitle(title: "訂閱")
                Subtitle(text: "管理節點來源與更新", divider: false)
                Spacer()
                Button { s.updateAllSubscriptions() } label: { Label("全部更新", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(GhostButton())
                    .disabled(s.store.subscriptions.isEmpty || !s.coreReady)
                Button { addNew() } label: { Label("新增訂閱", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
            }

            HStack(alignment: .top, spacing: 22) {
                ScrollView {
                    VStack(spacing: 20) {
                        if s.store.subscriptions.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "link.badge.plus").font(.system(size: 36)).foregroundColor(T.mute)
                                Text("還沒有訂閱").font(.system(size: 18, weight: .semibold))
                                Text("按右上角「新增訂閱」，貼上機場給你的訂閱連結").foregroundColor(T.mute)
                            }
                            .frame(maxWidth: .infinity, minHeight: 260)
                            .card()
                        }
                        ForEach(s.store.subscriptions) { sub in
                            card(sub)
                        }
                    }
                    .padding(2)
                }
                .frame(maxWidth: .infinity)

                editor
                    .frame(width: 480)
            }
            .frame(maxHeight: .infinity, alignment: .top)

            Divider().overlay(T.line)
            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                Text(showURL ? "訂閱連結目前顯示中" : "訂閱連結已隱藏")
            }
            .font(.system(size: 15))
            .foregroundColor(T.text.opacity(0.85))
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .onAppear {
            if selectedID == nil, let f = s.store.subscriptions.first { pick(f) }
        }
    }

    private func pick(_ sub: Subscription) {
        selectedID = sub.id
        draft = sub
        showURL = false
    }

    private func addNew() {
        let n = Subscription(name: "新訂閱 \(s.store.subscriptions.count + 1)", url: "")
        s.store.subscriptions.append(n)
        pick(n)
    }

    private func binding(_ id: UUID, _ kp: WritableKeyPath<Subscription, Bool>) -> Binding<Bool> {
        Binding(
            get: { s.store.subscriptions.first { $0.id == id }?[keyPath: kp] ?? false },
            set: { v in
                guard let i = s.store.subscriptions.firstIndex(where: { $0.id == id }) else { return }
                s.store.subscriptions[i][keyPath: kp] = v
                if draft?.id == id { draft?[keyPath: kp] = v }
                Task { await s.applyConfig() }
            })
    }

    @ViewBuilder
    private func card(_ sub: Subscription) -> some View {
        let isSel = sub.id == selectedID
        let updating = s.updatingSubs.contains(sub.id)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                CheckBox(isOn: binding(sub.id, \.enabled))
                Text(sub.name).font(.system(size: 22, weight: .semibold)).lineLimit(1)
                Tag(text: sub.enabled ? "已啟用" : "已停用", kind: sub.enabled ? .green : .gray)
                Spacer()
                SkySwitch(isOn: binding(sub.id, \.enabled), label: "啟用 \(sub.name)")
                Menu {
                    Button("編輯") { pick(sub) }
                    Button("複製訂閱連結") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(sub.url, forType: .string)
                        s.showToast("已複製訂閱連結")
                    }
                    Divider()
                    Button("刪除訂閱", role: .destructive) { delete(sub) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .bold)).foregroundColor(T.text)
                        .frame(width: 40, height: 36).contentShape(Rectangle())
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
                Button(updating ? "更新中" : "更新") { s.updateSubscription(sub.id) }
                    .buttonStyle(GhostButton(compact: true))
                    .disabled(updating || sub.url.isEmpty || !sub.enabled || !s.coreReady)
            }
            HStack(spacing: 14) {
                Image(systemName: "server.rack")
                Text("節點數：\(s.subNodeCount(sub).map(String.init) ?? "—")")
                Rectangle().fill(T.line).frame(width: 1, height: 20)
                Image(systemName: "arrow.clockwise")
                Text("最後更新：\(Fmt.ago(s.subUpdatedAt(sub)))")
            }
            .font(.system(size: 17))
            .foregroundColor(T.text.opacity(0.9))

            if sub.enabled {
                Divider().overlay(T.line)
                if let info = s.subInfo(sub) {
                    let used = (info.Download ?? 0) + (info.Upload ?? 0)
                    let total = max(1, info.Total ?? 1)
                    HStack {
                        Text("方案流量（來源提供）")
                        Spacer()
                        Text("已用 \(Fmt.bytes(used)) / \(Fmt.bytes(total))").monospacedDigit()
                    }
                    .font(.system(size: 17))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: 0x3A3D44))
                            Capsule().fill(T.accent).frame(width: max(14, g.size.width * min(1, CGFloat(used) / CGFloat(total))))
                        }
                    }
                    .frame(height: 16)
                    if let exp = info.Expire, exp > 0 {
                        Text("到期：\(Date(timeIntervalSince1970: TimeInterval(exp)).formatted(date: .numeric, time: .omitted))")
                            .font(.system(size: 14)).foregroundColor(T.mute)
                    }
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "info.circle")
                        Text("流量資訊未提供")
                    }
                    .font(.system(size: 17))
                    .foregroundColor(T.text.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .background(T.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSel ? T.accent : T.line, lineWidth: isSel ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { pick(sub) }
    }

    private func delete(_ sub: Subscription) {
        s.store.subscriptions.removeAll { $0.id == sub.id }
        try? FileManager.default.removeItem(at: ConfigBuilder.providerFile(sub.providerName, workDir: s.workDir))
        if selectedID == sub.id { selectedID = nil; draft = nil; if let f = s.store.subscriptions.first { pick(f) } }
        Task { await s.applyConfig() }
    }

    @ViewBuilder
    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let d = Binding($draft) {
              ScrollView {
               VStack(alignment: .leading, spacing: 14) {
                Text(d.wrappedValue.name.isEmpty ? "未命名" : d.wrappedValue.name).font(.system(size: 26, weight: .bold)).lineLimit(1)
                Text("訂閱名稱").font(.system(size: 17))
                TextField("例如：主要訂閱", text: d.name).skyField()
                Text("訂閱連結").font(.system(size: 17)).padding(.top, 4)
                HStack {
                    Group {
                        if showURL {
                            TextField("https://", text: d.url)
                        } else {
                            SecureField("https://", text: d.url)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    Button { showURL.toggle() } label: {
                        Image(systemName: showURL ? "eye.slash" : "eye").font(.system(size: 17)).foregroundColor(T.text)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showURL ? "隱藏連結" : "顯示連結")
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(T.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line))

                Divider().overlay(T.line).padding(.vertical, 4)
                HStack {
                    Text("自動更新").font(.system(size: 17))
                    Spacer()
                    SkySwitch(isOn: d.autoUpdate, label: "自動更新")
                }
                if d.wrappedValue.autoUpdate {
                    HStack {
                        Text("更新間隔").font(.system(size: 17)).padding(.leading, 18)
                        Spacer()
                        Dropdown(options: [(1, "每 1 小時"), (3, "每 3 小時"), (6, "每 6 小時"), (12, "每 12 小時"), (24, "每 24 小時")],
                                 selection: d.intervalHours)
                            .frame(width: 230)
                    }
                }
                Divider().overlay(T.line).padding(.vertical, 4)
                HStack(spacing: 10) {
                    Text("透過目前代理更新").font(.system(size: 17))
                    Image(systemName: "info.circle").foregroundColor(T.text.opacity(0.8))
                        .help("用目前選擇的節點下載訂閱；第一次下載時還沒有節點，會先直接連線")
                    Spacer()
                    SkySwitch(isOn: d.viaProxy, label: "透過目前代理更新")
                }
                Divider().overlay(T.line).padding(.vertical, 4)
                Text("更新狀態").font(.system(size: 17))
                if s.updatingSubs.contains(d.wrappedValue.id) {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text("更新中…") }
                        .font(.system(size: 15)).foregroundColor(T.text)
                } else if let live = s.store.subscriptions.first(where: { $0.id == d.wrappedValue.id }), let ok = live.statusOK {
                    HStack(spacing: 10) {
                        Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(live.statusMessage ?? (ok ? "更新成功" : "更新失敗")).lineLimit(2)
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(ok ? T.accent : Color(hex: 0xFF8A8F))
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(ok ? T.pillBG : T.redDim, in: RoundedRectangle(cornerRadius: 9))
                } else {
                    Text("尚未更新").font(.system(size: 15)).foregroundColor(T.mute)
                }
               }
               .frame(maxWidth: .infinity, alignment: .leading)
              }
              .scrollIndicators(.never)
                Button("儲存變更") { saveDraft() }
                    .buttonStyle(PrimaryButton(full: true))
                    .disabled(d.wrappedValue.url.trimmingCharacters(in: .whitespaces).isEmpty)
            } else {
                Spacer()
                Text("選擇或新增一個訂閱").foregroundColor(T.mute).frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(T.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(T.line))
    }

    private func saveDraft() {
        guard var d = draft, let i = s.store.subscriptions.firstIndex(where: { $0.id == d.id }) else { return }
        d.url = d.url.trimmingCharacters(in: .whitespacesAndNewlines)
        d.name = d.name.trimmingCharacters(in: .whitespaces).ifEmpty("未命名訂閱")
        let urlChanged = s.store.subscriptions[i].url != d.url
        d.statusOK = s.store.subscriptions[i].statusOK
        d.statusMessage = s.store.subscriptions[i].statusMessage
        s.store.subscriptions[i] = d
        draft = d
        if urlChanged {
            try? FileManager.default.removeItem(at: ConfigBuilder.providerFile(d.providerName, workDir: s.workDir))
        }
        let id = d.id
        Task {
            await s.applyConfig()
            if urlChanged { s.updateSubscription(id) }
            s.showToast("已儲存")
        }
    }
}
