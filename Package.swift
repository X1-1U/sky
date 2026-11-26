// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sky",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Sky", path: "Sources/Sky"),
        // 單元測試：訂閱解析、設定檔產生、本機檔案伺服器（測試檔在 Tests/fixtures，與 Windows 版共用）
        .testTarget(name: "SkyTests", dependencies: ["Sky"], path: "Tests/SkyTests"),
    ]
)
