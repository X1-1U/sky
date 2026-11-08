import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

enum T {
    static let bg = Color(hex: 0x16171B)
    static let sidebar = Color(hex: 0x1E2024)
    static let card = Color(hex: 0x1B1D21)
    static let field = Color(hex: 0x24262B)
    static let header = Color(hex: 0x26282D)
    static let line = Color(hex: 0x30333A)
    static let text = Color(hex: 0xE8EAED)
    static let mute = Color(hex: 0x9EA2AA)
    static let accent = Color(hex: 0x3DDBB4)
    static let accentInk = Color(hex: 0x08261F)
    static let accentDim = Color(hex: 0x1F4A40)
    static let seg = Color(hex: 0x23866E)
    static let rowSel = Color(hex: 0x1C3F37)
    static let pillBG = Color(hex: 0x1A3A32)
    static let red = Color(hex: 0xF0646A)
    static let redDim = Color(hex: 0x4A2326)
    static let amber = Color(hex: 0xF5B94A)
}

// MARK: - 卡片

struct CardBG: ViewModifier {
    var padding: CGFloat
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(T.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(highlighted ? T.accent : T.line, lineWidth: highlighted ? 2 : 1))
    }
}

extension View {
    func card(_ padding: CGFloat = 18, highlighted: Bool = false) -> some View {
        modifier(CardBG(padding: padding, highlighted: highlighted))
    }
}

// MARK: - 按鈕

struct PrimaryButton: ButtonStyle {
    var full = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(T.accentInk)
            .padding(.horizontal, 18)
            .frame(maxWidth: full ? .infinity : nil, minHeight: 40)
            .background(T.accent.opacity(configuration.isPressed ? 0.75 : 1), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
    }
}

struct GhostButton: ButtonStyle {
    var full = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 14 : 15, weight: .medium))
            .foregroundColor(T.text)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(maxWidth: full ? .infinity : nil, minHeight: compact ? 34 : 40)
            .background(configuration.isPressed ? T.line : T.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line))
            .contentShape(Rectangle())
    }
}

struct DangerButton: ButtonStyle {
    var full = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(T.red)
            .padding(.horizontal, 18)
            .frame(maxWidth: full ? .infinity : nil, minHeight: 40)
            .background(configuration.isPressed ? T.redDim : Color.clear, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.red.opacity(0.8)))
            .contentShape(Rectangle())
    }
}

// MARK: - 開關

struct SkySwitch: View {
    @Binding var isOn: Bool
    var label = "開關"
    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? T.accent : Color(hex: 0x3A3D44)).frame(width: 46, height: 28)
                Circle().fill(Color.white).frame(width: 22, height: 22).padding(3)
                    .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "開啟" : "關閉")
    }
}

struct CheckBox: View {
    @Binding var isOn: Bool
    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 5)
                .fill(isOn ? T.accent : Color.clear)
                .frame(width: 22, height: 22)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(isOn ? T.accent : T.mute, lineWidth: 1.5))
                .overlay(Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(T.accentInk).opacity(isOn ? 1 : 0))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 分段選擇

struct Segmented<V: Hashable>: View {
    let options: [(V, String)]
    @Binding var selection: V
    var height: CGFloat = 40

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                if i > 0 && selection != o.0 && selection != options[i - 1].0 {
                    Rectangle().fill(T.line).frame(width: 1, height: height * 0.5)
                }
                Button { selection = o.0 } label: {
                    Text(o.1)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(selection == o.0 ? .white : T.text.opacity(0.85))
                        .frame(maxWidth: .infinity, minHeight: height - 6)
                        .background(selection == o.0 ? T.seg : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(T.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(selected ? T.accentInk : T.text)
                .padding(.horizontal, 20)
                .frame(minHeight: 40)
                .fixedSize()
                .background(selected ? T.accent : T.field, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : T.line))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 標籤

struct StatusPill: View {
    let text: String
    var on = true
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(on ? T.accent : T.mute).frame(width: 10, height: 10)
            Text(text).font(.system(size: 16, weight: .medium))
        }
        .foregroundColor(on ? T.accent : T.mute)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(on ? T.pillBG : T.field, in: Capsule())
    }
}

enum TagKind { case green, gray, red, solidGreen }

struct Tag: View {
    let text: String
    var kind: TagKind = .green
    var icon: String?
    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 13, weight: .semibold)) }
            Text(text).font(.system(size: 14, weight: .medium))
        }
        .foregroundColor(fg)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(bg, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(stroke))
    }
    private var fg: Color {
        switch kind { case .green: return T.accent; case .gray: return T.text.opacity(0.85); case .red: return Color(hex: 0xFF8A8F); case .solidGreen: return .white }
    }
    private var bg: Color {
        switch kind { case .green: return T.pillBG; case .gray: return T.header; case .red: return T.redDim; case .solidGreen: return T.seg }
    }
    private var stroke: Color {
        switch kind { case .green: return T.accent.opacity(0.35); case .gray: return T.line; case .red: return T.red.opacity(0.5); case .solidGreen: return .clear }
    }
}

// MARK: - 輸入

struct SearchField: View {
    let placeholder: String
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(T.mute).font(.system(size: 16))
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(.system(size: 15))
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(T.mute) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(T.field, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.line))
    }
}

struct FieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(T.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line))
    }
}

extension View {
    func skyField() -> some View { modifier(FieldStyle()) }
}

struct Dropdown<V: Hashable>: View {
    let options: [(V, String)]
    @Binding var selection: V
    var icon: ((V) -> String?)? = nil

    var body: some View {
        Menu {
            ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                Button(o.1) { selection = o.0 }
            }
        } label: {
            HStack(spacing: 10) {
                if let name = icon?(selection) { Image(systemName: name).foregroundColor(T.text) }
                Text(options.first { $0.0 == selection }?.1 ?? "").foregroundColor(T.text).font(.system(size: 15))
                Spacer(minLength: 8)
                Image(systemName: "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundColor(T.text)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(T.field, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(T.line))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }
}

// MARK: - 頁首

struct PageTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.system(size: 32, weight: .bold)).foregroundColor(T.text)
    }
}

struct Subtitle: View {
    let text: String
    var divider = true
    var body: some View {
        HStack(spacing: 14) {
            if divider { Rectangle().fill(T.line).frame(width: 1, height: 22) }
            Text(text).font(.system(size: 17)).foregroundColor(T.text.opacity(0.8))
        }
    }
}

// MARK: - 國旗

struct FlagView: View {
    let name: String
    var size: CGFloat = 20
    var body: some View {
        Group {
            if let c = Flags.code(for: name) {
                Text(Flags.emoji(c)).font(.system(size: size))
            } else {
                Image(systemName: "globe").font(.system(size: size * 0.8)).foregroundColor(T.mute)
            }
        }
        .frame(width: size * 1.6)
    }
}

// MARK: - 統計卡

struct StatCard: View {
    let icon: String
    let title: String
    let value: String
    var iconColor: Color = T.text
    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(systemName: icon).font(.system(size: 24, weight: .regular)).foregroundColor(iconColor).frame(width: 30).padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(size: 16)).foregroundColor(T.text.opacity(0.85))
                Text(value).font(.system(size: 30, weight: .medium)).monospacedDigit().foregroundColor(T.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .card(20)
    }
}

// MARK: - 表格

struct TableHeader: View {
    let columns: [(String, CGFloat?)]   // nil = 彈性寬度
    var leading: CGFloat = 0
    var body: some View {
        HStack(spacing: 0) {
            if leading > 0 { Color.clear.frame(width: leading) }
            ForEach(Array(columns.enumerated()), id: \.offset) { _, c in
                if let w = c.1 {
                    Text(c.0).frame(width: w, alignment: .leading)
                } else {
                    Text(c.0).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(T.text.opacity(0.9))
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(T.header, in: RoundedRectangle(cornerRadius: 8))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundColor(T.text.opacity(0.9))
            Spacer()
            Text(value).foregroundColor(T.text).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
        }
        .font(.system(size: 16))
    }
}
