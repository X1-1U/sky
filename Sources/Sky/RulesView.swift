import SwiftUI

struct RulesView: View {
    @EnvironmentObject var s: AppState
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var draft: Rule?
    @State private var testInput = "https://example.com"
    @State private var testResult: RuleMatcher.Result?
    @State private var showImport = false
    @State private var dirty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                PageTitle(title: "規則")
                Subtitle(text: "依順序比對，優先套用第一條符合的規則")
                Spacer()
                Button { showImport = true } label: { Label("匯入", systemImage: "square.and.arrow.down") }
                    .buttonStyle(GhostButton())
                Button { addRule() } label: { Label("新增規則", systemImage: "plus") }
                    .buttonStyle(PrimaryButton())
            }

            HStack(spacing: 20) {
                Segmented(options: [("rule", "規則"), ("global", "全域"), ("direct", "直連")],
                          selection: Binding(get: { s.store.settings.mode }, set: { s.setMode($0) }))
                    .frame(minWidth: 220, maxWidth: 340)
                Rectangle().fill(T.line).frame(width: 1, height: 36)
                if let prof = s.profileSub {
                    Label("使用訂閱「\(prof.name)」的規則，你的規則優先", systemImage: "doc.text")
                        .font(.system(size: 15)).foregroundColor(T.text.opacity(0.85)).lineLimit(1)
                } else {
                    Text("預設策略：").font(.system(size: 17)).fixedSize()
                    Dropdown(options: RulePolicy.allCases.map { ($0, $0.rawValue) },
                             selection: Binding(get: { s.store.settings.defaultPolicy },
                                                set: { s.store.settings.defaultPolicy = $0; Task { await s.applyConfig() } }))
                        .frame(minWidth: 130, maxWidth: 200)
                }
                Spacer(minLength: 0)
                SearchField(placeholder: "搜尋規則", text: $search).frame(minWidth: 160, maxWidth: 340)
            }
            .padding(14)
            .background(T.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))

            HStack(alignment: .top, spacing: 18) {
                table
                editor.frame(width: 320)
            }
            .frame(maxHeight: .infinity)

            testBar
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 20)
        .sheet(isPresented: $showImport) { ImportRulesSheet { importRules($0) } }
    }

    // MARK: 表格

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 44)
                Text("#").frame(width: 50, alignment: .leading)
                Text("啟用").frame(width: 90, alignment: .leading)
                Text("類型").frame(width: 170, alignment: .leading)
                Text("比對內容").frame(maxWidth: .infinity, alignment: .leading)
                Text("策略").frame(width: 120, alignment: .leading)
            }
            .font(.system(size: 16, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 64)
            Divider().overlay(T.line)

            List {
                ForEach(Array(s.store.rules.enumerated()), id: \.element.id) { i, r in
                    if search.isEmpty || r.payload.localizedCaseInsensitiveContains(search) || r.type.localizedCaseInsensitiveContains(search) {
                        ruleRow(i, r)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .onMove { from, to in
                    s.store.rules.move(fromOffsets: from, toOffset: to)
                    Task { await s.applyConfig() }
                }
                if let prof = s.profileSub {
                    let subRules = s.profileRules(prof)
                    HStack {
                        Image(systemName: "doc.text").foregroundColor(T.mute)
                        Text("以下是訂閱「\(prof.name)」的 \(subRules.count) 條規則（唯讀，隨訂閱更新）")
                        Spacer()
                    }
                    .font(.system(size: 14, weight: .medium)).foregroundColor(T.text.opacity(0.85))
                    .padding(.horizontal, 16).frame(height: 44)
                    .background(T.header)
                    .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear).moveDisabled(true)
                    ForEach(Array(subRules.enumerated()), id: \.offset) { i, raw in
                        if search.isEmpty || raw.localizedCaseInsensitiveContains(search) {
                            subRuleRow(s.store.rules.count + i + 1, raw)
                                .listRowInsets(EdgeInsets()).listRowSeparator(.hidden).listRowBackground(Color.clear).moveDisabled(true)
                        }
                    }
                } else {
                    matchRow
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .moveDisabled(true)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
    }

    private func policyTag(_ p: RulePolicy) -> some View {
        Tag(text: p.rawValue, kind: p == .reject ? .red : (p == .direct ? .gray : .green), icon: p.icon)
    }

    private func ruleRow(_ i: Int, _ r: Rule) -> some View {
        let sel = r.id == selectedID
        return HStack(spacing: 0) {
            Image(systemName: "line.3.horizontal").foregroundColor(T.mute).frame(width: 44)
            Text("\(i + 1)").monospacedDigit().frame(width: 50, alignment: .leading)
            SkySwitch(isOn: Binding(get: { r.enabled }, set: { v in
                guard let idx = s.store.rules.firstIndex(where: { $0.id == r.id }) else { return }
                s.store.rules[idx].enabled = v
                if draft?.id == r.id { draft?.enabled = v }
                Task { await s.applyConfig() }
            }), label: "啟用規則 \(i + 1)")
            .frame(width: 90, alignment: .leading)
            Text(r.type).lineLimit(1).minimumScaleFactor(0.8).frame(width: 170, alignment: .leading)
            Text(r.payload).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
            policyTag(r.policy).frame(width: 120, alignment: .leading)
        }
        .font(.system(size: 17))
        .foregroundColor(T.text)
        .padding(.horizontal, 10)
        .frame(height: 64)
        .background(sel ? T.rowSel : Color.clear)
        .overlay(alignment: .bottom) { Divider().overlay(T.line) }
        .contentShape(Rectangle())
        .onTapGesture { selectedID = r.id; draft = r; dirty = false }
    }

    /// 訂閱規則一列：TYPE,內容,策略（AND/OR 這類複合規則整串顯示）
    private func subRuleRow(_ n: Int, _ raw: String) -> some View {
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let compound = raw.hasPrefix("AND") || raw.hasPrefix("OR") || raw.hasPrefix("NOT") || raw.hasPrefix("SUB-RULE")
        let type = parts.first ?? ""
        let payload = compound ? raw : (parts.count > 2 ? parts[1] : (type == "MATCH" ? "其他連線" : ""))
        let target = compound ? (parts.last ?? "") : (parts.count > 2 ? parts[2] : (parts.count == 2 ? parts[1] : ""))
        return HStack(spacing: 0) {
            Color.clear.frame(width: 44)
            Text("\(n)").monospacedDigit().frame(width: 50, alignment: .leading)
            Color.clear.frame(width: 90)
            Text(compound ? (type.split(separator: ",").first.map(String.init) ?? type) : type).lineLimit(1).frame(width: 170, alignment: .leading)
            Text(payload).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).help(raw)
            Tag(text: target, kind: target == "REJECT" ? .red : (target == "DIRECT" || target.contains("直连") || target.contains("直連") ? .gray : .green))
                .lineLimit(1).frame(width: 120, alignment: .leading)
        }
        .font(.system(size: 16))
        .foregroundColor(T.text.opacity(0.75))
        .padding(.horizontal, 10)
        .frame(height: 54)
        .overlay(alignment: .bottom) { Divider().overlay(T.line) }
    }

    private var matchRow: some View {
        HStack(spacing: 0) {
            Image(systemName: "lock").foregroundColor(T.mute).font(.system(size: 13)).frame(width: 44)
            Text("\(s.store.rules.count + 1)").monospacedDigit().frame(width: 50, alignment: .leading)
            Color.clear.frame(width: 90)
            Text("MATCH").frame(width: 170, alignment: .leading)
            Text("其他連線").frame(maxWidth: .infinity, alignment: .leading)
            policyTag(s.store.settings.defaultPolicy).frame(width: 120, alignment: .leading)
        }
        .font(.system(size: 17))
        .foregroundColor(T.text)
        .padding(.horizontal, 10)
        .frame(height: 64)
        .help("最後一條：沒被上面規則命中的連線都走「預設策略」")
    }

    // MARK: 編輯

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft == nil ? "編輯規則" : (s.store.rules.contains { $0.id == draft?.id } ? "編輯規則" : "新增規則"))
                .font(.system(size: 24, weight: .bold))
            if let d = Binding($draft) {
                Text("類型").font(.system(size: 17)).padding(.top, 6)
                Dropdown(options: Rule.types.map { ($0, $0) }, selection: d.type)
                Text("比對內容").font(.system(size: 17)).padding(.top, 6)
                TextField(placeholder(d.wrappedValue.type), text: d.payload).skyField()
                Text("策略").font(.system(size: 17)).padding(.top, 6)
                Dropdown(options: RulePolicy.allCases.map { ($0, $0.rawValue) }, selection: d.policy, icon: { $0.icon })
                HStack {
                    Text("啟用").font(.system(size: 17))
                    Spacer()
                    SkySwitch(isOn: d.enabled, label: "啟用")
                }
                .padding(.top, 10)
                Spacer(minLength: 16)
                Button("儲存變更") { saveDraft() }
                    .buttonStyle(PrimaryButton(full: true))
                    .disabled(d.wrappedValue.payload.trimmingCharacters(in: .whitespaces).isEmpty)
                if s.store.rules.contains(where: { $0.id == d.wrappedValue.id }) {
                    Button("刪除規則") { deleteDraft() }.buttonStyle(DangerButton(full: true))
                }
            } else {
                Spacer()
                Text("點選左邊的規則來編輯，或按「新增規則」").foregroundColor(T.mute).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(T.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
    }

    private func placeholder(_ type: String) -> String {
        switch type {
        case "DOMAIN-SUFFIX": return "example.com"
        case "DOMAIN": return "www.example.com"
        case "DOMAIN-KEYWORD": return "google"
        case "IP-CIDR", "SRC-IP-CIDR": return "192.168.0.0/16"
        case "IP-CIDR6": return "2001:db8::/32"
        case "DST-PORT": return "443"
        case "PROCESS-NAME": return "Telegram"
        case "GEOIP": return "CN"
        case "GEOSITE": return "google"
        default: return ""
        }
    }

    private func addRule() {
        let r = Rule(type: "DOMAIN-SUFFIX", payload: "", policy: .proxy)
        selectedID = r.id
        draft = r
    }

    private func saveDraft() {
        guard var d = draft else { return }
        d.payload = d.payload.trimmingCharacters(in: .whitespaces)
        if let i = s.store.rules.firstIndex(where: { $0.id == d.id }) {
            s.store.rules[i] = d
        } else {
            s.store.rules.insert(d, at: 0)    // 新規則放最前面，優先比對
        }
        draft = d
        Task { await s.applyConfig(); s.showToast("規則已套用") }
    }

    private func deleteDraft() {
        guard let d = draft else { return }
        s.store.rules.removeAll { $0.id == d.id }
        draft = nil
        selectedID = nil
        Task { await s.applyConfig() }
    }

    private func importRules(_ text: String) {
        var added = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("- ") { line = String(line.dropFirst(2)) }
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            let parts = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2, Rule.types.contains(parts[0].uppercased()) else { continue }
            let pol: RulePolicy
            switch (parts.count > 2 ? parts[2] : "").uppercased() {
            case "DIRECT", "直連": pol = .direct
            case "REJECT", "REJECT-DROP", "拒絕": pol = .reject
            case "自動選擇": pol = .auto
            default: pol = .proxy
            }
            s.store.rules.append(Rule(type: parts[0].uppercased(), payload: parts[1], policy: pol))
            added += 1
        }
        Task { await s.applyConfig(); s.showToast(added > 0 ? "已匯入 \(added) 條規則" : "沒有可匯入的規則") }
    }

    // MARK: 測試

    private var testBar: some View {
        HStack(spacing: 18) {
            Text("測試規則").font(.system(size: 20, weight: .semibold)).fixedSize()
            TextField("網址或網域", text: $testInput).skyField().onSubmit(runTest)
            Button("測試", action: runTest).buttonStyle(PrimaryButton()).frame(width: 100)
            Rectangle().fill(T.line).frame(width: 1, height: 36)
            Group {
                if let r = testResult {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle").font(.system(size: 20))
                        if let i = r.index {
                            Text("命中第 \(i + 1) 條 · \(r.policy.rawValue)")
                        } else {
                            Text("未命中 · 使用預設策略 \(r.policy.rawValue)")
                        }
                    }
                    .help(r.note ?? "")
                } else {
                    Text("輸入網址後按「測試」").foregroundColor(T.mute)
                }
            }
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(T.accent)
            .lineLimit(1)
            .padding(.horizontal, 18)
            .frame(minWidth: 200, maxWidth: 360, minHeight: 46, maxHeight: 46, alignment: .leading)
            .background(T.pillBG.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(18)
        .background(T.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.line))
    }

    private func runTest() {
        testResult = RuleMatcher.match(testInput, rules: s.store.rules, defaultPolicy: s.store.settings.defaultPolicy)
    }
}

struct ImportRulesSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    let onImport: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("匯入規則").font(.system(size: 22, weight: .bold))
            Text("一行一條，格式：類型,內容,策略（例如 DOMAIN-SUFFIX,google.com,代理）。策略可寫 代理 / 直連 / 拒絕 或 DIRECT / REJECT；可直接貼 Clash 設定檔裡 rules: 底下的內容。")
                .font(.system(size: 14)).foregroundColor(T.mute)
            TextEditor(text: $text)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .background(T.field, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line))
                .frame(height: 240)
            HStack {
                Button("從剪貼簿貼上") { text = NSPasteboard.general.string(forType: .string) ?? "" }.buttonStyle(GhostButton(compact: true))
                Spacer()
                Button("取消") { dismiss() }.buttonStyle(GhostButton(compact: true))
                Button("匯入") { onImport(text); dismiss() }.buttonStyle(PrimaryButton())
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(T.card)
    }
}
