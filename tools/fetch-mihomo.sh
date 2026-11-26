#!/bin/bash
# 從 mihomo 官方 GitHub Release 下載核心，並用 GitHub 提供的 SHA-256 驗證後才解壓
# 用法：tools/fetch-mihomo.sh darwin|windows <輸出路徑>
#   darwin  → 輸出 Apple 晶片版執行檔
#   windows → 輸出 mihomo.exe（相容版，支援較舊的 CPU）
# 環境變數 MIHOMO_VERSION=v1.19.34 可固定版本；不設就用最新版
set -euo pipefail

platform="${1:?需要 darwin 或 windows}"
out="${2:?需要輸出路徑}"
repo="MetaCubeX/mihomo"
api="https://api.github.com/repos/$repo/releases/${MIHOMO_VERSION:+tags/}${MIHOMO_VERSION:-latest}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 ${GITHUB_TOKEN:+-H "Authorization: Bearer $GITHUB_TOKEN"} "$api" -o "$tmp/release.json"

# 從發佈資訊找出要的檔案、下載網址與雜湊值
python3 - "$platform" "$tmp/release.json" > "$tmp/asset.txt" <<'PY'
import json, sys
platform, path = sys.argv[1], sys.argv[2]
d = json.load(open(path))
tag = d["tag_name"]
want = {"darwin": f"mihomo-darwin-arm64-{tag}.gz",
        "windows": f"mihomo-windows-amd64-compatible-{tag}.zip"}[platform]
for a in d["assets"]:
    if a["name"] == want:
        dg = a.get("digest") or ""
        if not dg.startswith("sha256:"):
            sys.exit(f"{want} 沒有提供 SHA-256，拒絕使用")
        print(tag, want, a["browser_download_url"], dg[7:])
        break
else:
    sys.exit(f"Release {tag} 裡找不到 {want}")
PY
read -r tag name url digest < "$tmp/asset.txt"

echo "下載 mihomo ${tag}：${name}"
curl -fsSL --retry 3 "$url" -o "$tmp/$name"

# 驗證雜湊值（macOS 用 shasum，Windows 的 Git Bash 用 sha256sum）
if command -v shasum >/dev/null; then actual="$(shasum -a 256 "$tmp/$name" | cut -d' ' -f1)"
else actual="$(sha256sum "$tmp/$name" | cut -d' ' -f1)"; fi
if [ "$actual" != "$digest" ]; then
  echo "SHA-256 不符！預期 ${digest}，實際 ${actual}" >&2
  exit 1
fi
echo "SHA-256 驗證通過"

mkdir -p "$(dirname "$out")"
case "$platform" in
  darwin)  gunzip -c "$tmp/$name" > "$out"; chmod +x "$out" ;;
  windows) (cd "$tmp" && unzip -q -o "$name") && mv "$tmp"/mihomo-windows-amd64-compatible*.exe "$out" ;;
esac
echo "$tag" > "$out.version"
echo "已輸出 ${out}（${tag}）"
