import Foundation

/// 每秒都會變的資料（速度、流量圖、連線）。獨立成一個物件，
/// 只有總覽、連線頁、選單列面板訂閱它，其他頁面不會因此每秒重畫。
@MainActor
final class LiveStats: ObservableObject {
    @Published var downSpeed: Double = 0
    @Published var upSpeed: Double = 0
    @Published var history: [SpeedSample] = []
    @Published var connections: [Conn] = []
    @Published var connHistory: [String: [SpeedSample]] = [:]
    @Published var activeCount = 0
    @Published var pausedConnections = false
}
