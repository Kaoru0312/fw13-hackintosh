#!/bin/bash
# 在 display override 裡放合成 EDID（IODisplayEDID）＋ HiDPI 縮放清單，讓 CoreDisplay 知道面板是 285×190 mm、約 201 PPI。
#   - 驅動端（PhxAccel hidpi2）的 connect probe 有觸發，但已存在的 AppleBacklightDisplay 沒有重讀 EDID，所以改從使用者層給。
#   - EDID 由 display/make-edid.py 產生（跟 phxfb.cpp getDDCBlock 一致：vendor FRW=0x1a57、product 1）。
#   - 兩個 override 都寫（同內容）：目前的身分 756e6b6e/717，以及 EDID 生效後的身分 1a57/1。
#   - scale-resolutions（backing 像素 → 看起來像）：2256×1504→1128×752、2560×1706→1280×853、2880×1920→1440×960、3008×2006→1504×1003。
#   - 原本整個 Overrides 資料夾備份到 /Users/Shared/gpu/display-overrides.bak-1121
#
# 用法：
#   sudo bash /Users/kaoru/fw13-hackintosh/display/edid-override.sh
# 之後重開機（或登出再登入）。
#
# 出問題才用（現在不要執行）：
#   sudo sh -c 'rm -rf /Library/Displays/Contents/Resources/Overrides && cp -R /Users/Shared/gpu/display-overrides.bak-1121 /Library/Displays/Contents/Resources/Overrides'
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OV=/Library/Displays/Contents/Resources/Overrides
BAK=/Users/Shared/gpu/display-overrides.bak-1121
EDID=$HERE/fw13-edid.bin

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$EDID" ] && [ "$(stat -f %z "$EDID")" = 128 ] || { echo "找不到 128 bytes 的 ${EDID}（先跑 display/make-edid.py）"; exit 1; }
[ -d "$OV" ] || { echo "找不到 ${OV}"; exit 1; }
[ -e "$BAK" ] && { echo "${BAK} 已存在，停止（可能已經跑過）"; exit 1; }

echo "== 1. 備份 Overrides"
cp -R "$OV" "$BAK"
echo "  → ${BAK}"

echo "== 2. 寫入兩份 override"
/usr/bin/python3 -I - "$OV" "$EDID" <<'EOF'
import plistlib, struct, sys, os
ov, edid_path = sys.argv[1], sys.argv[2]
edid = open(edid_path, "rb").read()
def sr(w, h):
    return struct.pack(">IIII", w, h, 1, 0x00200000)
scales = [sr(2256, 1504), sr(2560, 1706), sr(2880, 1920), sr(3008, 2006)]
for vid, pid in ((0x756E6B6E, 0x717), (0x1A57, 0x1)):
    d = os.path.join(ov, "DisplayVendorID-%x" % vid)
    os.makedirs(d, exist_ok=True)
    p = os.path.join(d, "DisplayProductID-%x" % pid)
    plist = {
        "DisplayProductName": "Framework 13",
        "DisplayVendorID": vid,
        "DisplayProductID": pid,
        "DisplayHorizontalImageSize": 285,
        "DisplayVerticalImageSize": 190,
        "IODisplayEDID": edid,
        "scale-resolutions": scales,
    }
    with open(p, "wb") as f:
        plistlib.dump(plist, f)
    os.chmod(p, 0o644)
    print("  %s（%d 個縮放、EDID %d bytes）" % (p, len(scales), len(edid)))
EOF
chown -R root:wheel "$OV"
plutil -lint "$OV/DisplayVendorID-756e6b6e/DisplayProductID-717" "$OV/DisplayVendorID-1a57/DisplayProductID-1"

echo ""
echo "完成。重開機（或登出再登入）後到「系統設定 → 顯示器」看縮放選項。"
