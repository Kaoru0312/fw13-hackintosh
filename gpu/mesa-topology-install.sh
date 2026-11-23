#!/bin/bash
# 換上「canned phoenix 拓撲改成 FW13 760M 實測值」的 libvulkan_radeon.dylib（gpu/mesa-topology-patch.py 產生，只改 4 bytes），
# 並 ad-hoc 重新簽章（保留原 identifier）。這是 macOS 系統上的檔案，不是 ESP。
#   - 原檔備份到 /Users/Shared/gpu/libvulkan_radeon.dylib.v040
#   - WindowServer 已經載入舊版，要重開機才會用新版
#   - 這一步還不會讓一般 App 用 GPU（phxboot 允許清單不變）
#
# 用法：
#   sudo bash /Users/kaoru/fw13-hackintosh/gpu/mesa-topology-install.sh
#
# 出問題才用（現在不要執行）：
#   sudo bash /Users/kaoru/fw13-hackintosh/gpu/mesa-topology-install.sh --restore
#   （如果開機後畫面異常，phxboot 會自動建立 phxboot-off 退回 CPU 繪製，登入後再跑上面這行還原）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
D=/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU/nvmtl/libvulkan_radeon.dylib
BAK=/Users/Shared/gpu/libvulkan_radeon.dylib.v040
NEW=$HERE/build/libvulkan_radeon.dylib
ORIG_SHA=1f2181d1183fa95f33eb3f626c96aa27fa242e4e96c49f6785fa7e53ee128f78

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }

if [ "${1:-}" = "--restore" ]; then
    [ -f "$BAK" ] || { echo "找不到備份 $BAK"; exit 1; }
    [ "$(shasum -a 256 "$BAK" | awk '{print $1}')" = "$ORIG_SHA" ] || { echo "備份的 sha 不對，停止"; exit 1; }
    cp "$BAK" "$D"
    codesign -v "$D" && echo "已還原原版（簽章有效）。重開機生效。"
    exit 0
fi

[ -f "$NEW" ] || { echo "找不到 ${NEW}（先跑 gpu/mesa-topology-patch.py）"; exit 1; }
CUR=$(shasum -a 256 "$D" | awk '{print $1}')
[ "$CUR" = "$ORIG_SHA" ] || { echo "系統上的 dylib 不是 v0.4.0 原版（sha ${CUR:0:16}…），停止"; exit 1; }
[ -e "$BAK" ] && { echo "$BAK 已存在，停止（可能已經跑過）"; exit 1; }
ID=$(codesign -dv "$D" 2>&1 | sed -n 's/^Identifier=//p')
[ -n "$ID" ] || { echo "讀不到原檔的簽章 identifier，停止"; exit 1; }

echo "== 1. 備份原檔"
cp -p "$D" "$BAK"
echo "  → $BAK"

echo "== 2. 簽章後換上新檔"
TMP=$(mktemp /private/tmp/libvulkan_radeon.XXXXXX)
cp "$NEW" "$TMP"
codesign -f -s - -i "$ID" "$TMP"
codesign -v "$TMP" || { echo "新檔簽章驗證失敗，停止（原檔未動）"; rm -f "$TMP"; exit 1; }
cp "$TMP" "$D"
rm -f "$TMP"
chown root:wheel "$D"; chmod 755 "$D"
codesign -v "$D" && echo "  簽章有效（identifier ${ID}）"
echo "  差異：$(cmp -l "$BAK" "$D" 2>/dev/null | wc -l | tr -d ' ') bytes（含簽章區）"

echo ""
echo "完成。重開機後 WindowServer 才會用新版。"
echo "開機後檢查：/var/log/phxboot.log 最後一段有 done、/Users/kaoru/fw13-hackintosh/nullarc-test/mtlprobe 結果 4096/4096"
