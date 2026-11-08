#!/bin/zsh
# 編譯 Sky（mihomo 圖形介面）並安裝到 /Applications
set -e
cd "$(dirname "$0")"

# 1. 核心：vendor/mihomo 不存在就從 GitHub 下載（失敗時改用 Clash Verge 內附的那份）
if [ ! -x vendor/mihomo ]; then
  mkdir -p vendor
  TAG=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep -m1 '"tag_name"' | cut -d'"' -f4)
  if [ -n "$TAG" ] && curl -fsL -o vendor/mihomo.gz "https://github.com/MetaCubeX/mihomo/releases/download/$TAG/mihomo-darwin-arm64-$TAG.gz"; then
    gunzip -f vendor/mihomo.gz
  elif [ -x "/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" ]; then
    cp "/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" vendor/mihomo
  else
    echo "找不到 mihomo 核心，請手動放到 vendor/mihomo"; exit 1
  fi
  chmod +x vendor/mihomo
fi

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
cat > "$APP/Contents/Info.plist" <<'P'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Sky</string>
<key>CFBundleDisplayName</key><string>Sky</string>
<key>CFBundleIdentifier</key><string>com.onsunday.sky</string>
<key>CFBundleExecutable</key><string>Sky</string>
<key>CFBundleIconFile</key><string>Sky</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleDevelopmentRegion</key><string>zh_TW</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P
codesign --force --sign - "$APP/Contents/Resources/mihomo"
codesign --force --sign - "$APP"

# 4. 安裝並開啟
osascript -e 'tell application "Sky" to quit' 2>/dev/null || true
sleep 1
pkill -x Sky 2>/dev/null || true
rm -rf /Applications/Sky.app
cp -R "$APP" /Applications/
open /Applications/Sky.app
echo "✅ 已安裝到 /Applications/Sky.app"
