#!/bin/zsh
# 編譯 Sky（mihomo 圖形介面）並安裝到 /Applications
set -e
cd "$(dirname "$0")"

# 1. 核心：只用 mihomo 官方 Release，並驗證 SHA-256（tools/fetch-mihomo.sh）
if [ ! -x vendor/mihomo ] || [ ! -f vendor/mihomo.version ]; then
  tools/fetch-mihomo.sh darwin vendor/mihomo
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
# 建置號：1.1.0 → 10100（必須遞增，macOS 用它判斷新舊）
BUILD_NUMBER="$(echo "$VERSION" | awk -F. '{ printf "%d%02d%02d", $1, $2, $3 }')"

# 2. 圖示
if [ ! -f build/Sky.icns ]; then
  mkdir -p build/Sky.iconset
  swift tools/makeicon.swift build/icon.png
  for s in 16 32 128 256 512; do
    sips -z $s $s build/icon.png --out build/Sky.iconset/icon_${s}x${s}.png >/dev/null
    sips -z $((s*2)) $((s*2)) build/icon.png --out build/Sky.iconset/icon_${s}x${s}@2x.png >/dev/null
  done
  iconutil -c icns build/Sky.iconset -o build/Sky.icns
fi

# 3. 編譯與打包
swift build -c release
APP=build/Sky.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Sky" "$APP/Contents/MacOS/"
cp vendor/mihomo "$APP/Contents/Resources/mihomo"
cp build/Sky.icns "$APP/Contents/Resources/Sky.icns"
cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Sky</string>
<key>CFBundleDisplayName</key><string>Sky</string>
<key>CFBundleIdentifier</key><string>com.onsunday.sky</string>
<key>CFBundleExecutable</key><string>Sky</string>
<key>CFBundleIconFile</key><string>Sky</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
<key>CFBundleDevelopmentRegion</key><string>zh_TW</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSLocationUsageDescription</key><string>Sky 需要定位權限才能讀取目前連線的 Wi-Fi 名稱，用來依 Wi-Fi 自動切換代理。</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Sky 需要定位權限才能讀取目前連線的 Wi-Fi 名稱，用來依 Wi-Fi 自動切換代理。</string>
</dict></plist>
P
codesign --force --sign - "$APP/Contents/Resources/mihomo"
codesign --force --sign - "$APP"

# 4. 打包成 zip（發佈用）
mkdir -p release
rm -f "release/Sky-${VERSION}-mac-arm64.zip"
ditto -c -k --keepParent "$APP" "release/Sky-${VERSION}-mac-arm64.zip"
echo "📦 release/Sky-${VERSION}-mac-arm64.zip"

# 5. 安裝並開啟（CI 或 --no-install 時跳過）
if [ "${1:-}" = "--no-install" ] || [ -n "${CI:-}" ]; then
  exit 0
fi
osascript -e 'tell application "Sky" to quit' 2>/dev/null || true
sleep 1
pkill -x Sky 2>/dev/null || true
rm -rf /Applications/Sky.app
cp -R "$APP" /Applications/
open /Applications/Sky.app
echo "✅ 已安裝到 /Applications/Sky.app"
