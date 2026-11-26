# Sky

以 [mihomo](https://github.com/MetaCubeX/mihomo) 為核心的代理工具，有 macOS 與 Windows 兩個版本，介面為繁體中文。

## 功能

- **總覽**：一鍵連線（系統代理）、延遲、即時上下傳速度與流量圖、目前節點、路由模式（規則／全域／直連）
- **節點**：搜尋、收藏、低延遲篩選、批次測速、延遲紀錄圖；可貼上 `ss://`、`vmess://`、`vless://`、`trojan://`、`hysteria2://` 等分享連結新增節點
- **訂閱**：多個訂閱、自動更新間隔、透過目前代理更新、顯示機場提供的流量與到期日
- **規則**：新增／編輯／拖曳排序、匯入 Clash 規則、測試網址會命中哪一條
- **連線**：即時連線列表、來源程式、命中規則、單條傳輸速率、中斷連線
- **TUN 模式**：接管所有程式的流量
- **更新檢查**：檢查 Sky 新版本（本 repo 的 Releases）與 mihomo 核心新版本，核心可在 App 內直接更新

## 下載

到 [Releases](https://github.com/X1-1U/sky/releases) 下載：

| 系統 | 檔案 |
|---|---|
| macOS 14 以上（Apple 晶片） | `Sky-<版本>-mac-arm64.zip` |
| Windows 10/11（x64） | `Sky-Setup-<版本>.exe`（安裝版）或 `Sky-<版本>-win-x64.zip`（免安裝） |

### 第一次打開

App 沒有經過 Apple／Microsoft 付費簽章，系統會擋：

- **macOS**：解壓縮後把 Sky.app 拖進「應用程式」，第一次在 Sky 上按右鍵 →「打開」。如果顯示「已損毀」，在終端機執行：
  ```bash
  xattr -cr /Applications/Sky.app   # 移除下載隔離標記
  ```
- **Windows**：出現「Windows 已保護您的電腦」時，按「其他資訊」→「仍要執行」。

### TUN 模式

- **macOS**：第一次開啟時輸入一次管理員密碼，Sky 會安裝系統背景服務（LaunchDaemon `com.onsunday.sky.core`），由它以 root 執行 mihomo。核心與工作資料夾（`/Library/Application Support/Sky/`）都屬於 root，Sky 只透過本機 API 推送設定。「設定」裡可以移除背景服務。
  - 1.0.x 版用 setuid 授權，有提權風險；更新到 1.1.0 後第一次啟動會提示升級，舊檔案會被刪除。
- **Windows**：需要以系統管理員身分執行，開啟時 Sky 會自動以系統管理員身分重新啟動。

### 區域網路

開啟「允許區域網路連線」後，同網路的手機、電視可以把代理設成這台電腦的 IP 與混合埠，但一定要輸入 Sky 產生的帳號密碼（在「設定 → 網路」）；本機程式免密碼。

## 從原始碼建置

mihomo 核心一律從[官方 Release](https://github.com/MetaCubeX/mihomo/releases) 下載，並比對 GitHub 提供的 SHA-256：

```bash
tools/fetch-mihomo.sh darwin vendor/mihomo                 # Mac 版核心
tools/fetch-mihomo.sh windows windows/vendor/mihomo.exe    # Windows 版核心
```

**macOS**（需要 Xcode / Swift 5.9 以上）：

```bash
swift test                 # 單元測試
./build.sh                 # 編譯、打包成 release/*.zip 並安裝到 /Applications
./build.sh --no-install    # 只打包不安裝
```

**Windows**（在 macOS 或 Windows 上都能打包，需要 Node.js）：

```bash
cd windows
npm ci
npm test                             # 單元測試（與 Mac 版共用 Tests/fixtures）
npx electron-builder --win --x64     # 產出 windows/dist/
```

### 發佈新版

1. 改 `VERSION` 與 `windows/package.json` 的 `version`（兩者要一致）
2. 在 `release-notes/v<版本>.md` 寫發佈說明
3. 推送標籤 `git tag v<版本> && git push origin v<版本>`，GitHub Actions 會測試、建置並上傳到 Release

## 資料位置

- macOS：`~/Library/Application Support/Sky`
- Windows：`%APPDATA%\Sky`

## 第三方元件

- [mihomo](https://github.com/MetaCubeX/mihomo)（GPL-3.0）：以獨立執行檔的形式隨附於安裝檔中，未經修改，原始碼請見其 repo。
- Windows 版使用 [Electron](https://www.electronjs.org/)、[Preact](https://preactjs.com/)、[htm](https://github.com/developit/htm)（MIT）。
