#!/bin/bash
# 把 build/H264VCNDecoder.bundle 裝到 /System/Library/Video/Plug-Ins（VideoToolbox 讀這裡的解碼外掛時不檢查簽章，
# 見 ryzenstatus-utils GPU/docs/how-it-works.md；/Library/Video/Plug-Ins 則要求 Apple 簽章）。
#   - 要能寫系統磁碟區（nullarc 安裝時也寫過 /System/Library/CoreServices/CoreTypes.bundle）；寫不進去就停止，什麼都不改。
#   - 外掛只在 VCN 已經帶起來（開機時 phxboot 的 vcnctl up）且 PhxBringup build ≥ 135 時才會接手，否則 VideoToolbox 照常用軟體解碼。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/vcn/vt/install.sh           安裝
#       sudo bash /Users/kaoru/fw13-hackintosh/vcn/vt/install.sh --remove  移除
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
D=/System/Library/Video/Plug-Ins
B=$D/H264VCNDecoder.bundle
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
if [ "${1:-}" = "--remove" ]; then
  rm -rf "$B" && echo "已移除 ${B}"
  killall VTDecoderXPCService 2>/dev/null; echo "（已結束正在跑的 VTDecoderXPCService，下次播放影片會重新載入外掛清單）"
  exit 0
fi
[ -f "$HERE/build/H264VCNDecoder.bundle/Contents/MacOS/H264VCNDecoder" ] || { echo "先跑 vcn/vt/build.sh"; exit 1; }
[ -d "$D" ] || { echo "找不到 ${D}"; exit 1; }
touch "$D/.fw13-write-test" 2>/dev/null && rm -f "$D/.fw13-write-test" || { echo "${D} 寫不進去（系統磁碟區是唯讀的），停止，什麼都沒改"; exit 1; }
rm -rf "$B.new" && ditto "$HERE/build/H264VCNDecoder.bundle" "$B.new" && rm -rf "$B" && mv "$B.new" "$B" || { echo "複製失敗"; exit 1; }
chown -R root:wheel "$B"; chmod -R go-w "$B"
codesign --verify "$B" 2>&1 | head -2
echo "已安裝 ${B}"
killall VTDecoderXPCService 2>/dev/null; echo "（已結束正在跑的 VTDecoderXPCService，下次播放影片會重新載入外掛清單）"
echo "移除：sudo bash $0 --remove"
