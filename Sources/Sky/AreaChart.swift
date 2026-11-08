import SwiftUI

/// 面積圖：主線（綠色填滿）＋ 次線（白色細線）
struct AreaChart: View {
    var primary: [Double]
    var secondary: [Double] = []
    var xLabels: [String] = []
    var format: (Double) -> String
    var ticks = 4
    var minMax: Double = 1
    var labelWidth: CGFloat = 70

    var body: some View {
        Canvas { ctx, size in
            let maxV = niceMax(max(minMax, (primary + secondary).max() ?? 0))
            let bottom: CGFloat = xLabels.isEmpty ? 4 : 26
            let plot = CGRect(x: labelWidth, y: 8, width: max(10, size.width - labelWidth - 6), height: max(10, size.height - 8 - bottom))
            let gridColor = T.line.opacity(0.7)

            for i in 0...ticks {
                let y = plot.maxY - plot.height * CGFloat(i) / CGFloat(ticks)
                var p = Path()
                p.move(to: CGPoint(x: plot.minX, y: y))
                p.addLine(to: CGPoint(x: plot.maxX, y: y))
                ctx.stroke(p, with: .color(gridColor), lineWidth: 0.6)
                ctx.draw(Text(format(maxV * Double(i) / Double(ticks))).font(.system(size: 12)).foregroundColor(T.text.opacity(0.8)),
                         at: CGPoint(x: labelWidth - 10, y: y), anchor: .trailing)
            }
            if !xLabels.isEmpty {
                for (i, l) in xLabels.enumerated() {
                    let x = plot.minX + plot.width * CGFloat(i) / CGFloat(max(1, xLabels.count - 1))
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: plot.minY))
                    p.addLine(to: CGPoint(x: x, y: plot.maxY))
                    ctx.stroke(p, with: .color(gridColor.opacity(0.6)), lineWidth: 0.5)
                    let anchor: UnitPoint = i == 0 ? .leading : (i == xLabels.count - 1 ? .trailing : .center)
                    ctx.draw(Text(l).font(.system(size: 12)).foregroundColor(T.text.opacity(0.8)),
                             at: CGPoint(x: x, y: plot.maxY + 14), anchor: anchor)
                }
            }
            // 左軸
            var axis = Path()
            axis.move(to: CGPoint(x: plot.minX, y: plot.minY))
            axis.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            ctx.stroke(axis, with: .color(T.line), lineWidth: 1)

            func points(_ v: [Double]) -> [CGPoint] {
                guard v.count > 1 else { return [] }
                return v.enumerated().map { i, val in
                    CGPoint(x: plot.minX + plot.width * CGFloat(i) / CGFloat(v.count - 1),
                            y: plot.maxY - plot.height * CGFloat(min(val, maxV) / maxV))
                }
            }

            let p1 = points(primary)
            if let first = p1.first, let last = p1.last {
                var line = Path()
                line.addLines(p1)
                var area = line
                area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                area.addLine(to: CGPoint(x: first.x, y: plot.maxY))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [T.accent.opacity(0.42), T.accent.opacity(0.04)]),
                                                     startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
                ctx.stroke(line, with: .color(T.accent), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
            }
            let p2 = points(secondary)
            if p2.count > 1 {
                var line = Path()
                line.addLines(p2)
                ctx.stroke(line, with: .color(Color.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
    }

    /// 速度用 1024 進位取整（例如 1 MB/s、512 KB/s），其他用十進位
    var bytesScale = false
    private func niceMax(_ v: Double) -> Double {
        guard bytesScale else { return AreaChart.nice(v) }
        let mb = 1024.0 * 1024
        if v >= mb { return AreaChart.nice(v / mb) * mb }
        if v >= 1024 { return AreaChart.nice(v / 1024) * 1024 }
        return AreaChart.nice(v)
    }

    static func nice(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let e = pow(10, floor(log10(v)))
        let f = v / e
        let n: Double = f <= 1 ? 1 : f <= 2 ? 2 : f <= 4 ? 4 : f <= 5 ? 5 : f <= 8 ? 8 : 10
        return n * e
    }

    static func speedLabel(_ v: Double) -> String {
        if v >= 1024 * 1024 { return String(format: "%g MB/s", (v / 1024 / 1024 * 100).rounded() / 100) }
        if v >= 1024 { return String(format: "%g KB/s", (v / 1024).rounded()) }
        return v == 0 ? "0 MB/s" : String(format: "%g B/s", v.rounded())
    }

    /// 取樣時間軸上平均分布的 n 個時間標籤
    static func timeLabels(_ dates: [Date], count: Int = 5, formatter: DateFormatter = Fmt.hms) -> [String] {
        guard dates.count > 1 else { return [] }
        return (0..<count).map { i in
            let idx = Int(Double(dates.count - 1) * Double(i) / Double(count - 1))
            return formatter.string(from: dates[idx])
        }
    }
}

struct Legend: View {
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(T.accent).frame(width: 11, height: 11); Text("下載") }
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 2).fill(T.mute).frame(width: 11, height: 11); Text("上傳") }
        }
        .font(.system(size: 15))
        .foregroundColor(T.text.opacity(0.85))
    }
}
