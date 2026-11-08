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

- **macOS**：第一次開啟時輸入一次管理員密碼，Sky 會把核心安裝到 `/Library/Application Support/Sky/` 並授權建立虛擬網卡；「設定」裡可以移除授權。
- **Windows**：需要以系統管理員身分執行，開啟時 Sky 會自動以系統管理員身分重新啟動。

## 從原始碼建置

**macOS**（需要 Xcode / Swift 5.9 以上）：

```bash
./build.sh   # 下載 mihomo、編譯、打包並安裝到 /Applications
```

**Windows**（在 macOS 或 Windows 上都能打包，需要 Node.js）：

```bash
cd windows
npm install
# 下載 mihomo-windows-amd64-compatible 並放到 windows/vendor/mihomo.exe
npx electron-builder --win --x64   # 產出 windows/dist/
```

## 資料位置

- macOS：`~/Library/Application Support/Sky`
- Windows：`%APPDATA%\Sky`

## 第三方元件

- [mihomo](https://github.com/MetaCubeX/mihomo)（GPL-3.0）：以獨立執行檔的形式隨附於安裝檔中，未經修改，原始碼請見其 repo。
- Windows 版使用 [Electron](https://www.electronjs.org/)、[Preact](https://preactjs.com/)、[htm](https://github.com/developit/htm)（MIT）。
