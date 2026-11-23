#!/bin/bash
# VoodooI2CHID 只接管觸控板（PIXA3854）：VoodooI2CHIDDevice personality 的比對條件
# 從 IOPropertyMatch compatible=PNP0C50（三個 I2C HID 裝置都符合）改成 IOPropertyMatch IOName=PIXA3854。
# （第一版用 IONameMatch，比對的是節點名稱 TPAD 而不是 PIXA3854，結果連觸控板都沒接管。）
# 兩個 EC HID 裝置（FRMW0004/0005）就不會被每 5 ms 輪詢。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/i2c/tpad-only.sh'
# 還原：sudo cp /tmp/int/EFI/OC/VoodooI2CHID-Info.plist.orig /tmp/int/EFI/OC/Kexts/VoodooI2CHID.kext/Contents/Info.plist
#       （CachyOS：sudo cp /boot/EFI/OC/VoodooI2CHID-Info.plist.orig /boot/EFI/OC/Kexts/VoodooI2CHID.kext/Contents/Info.plist）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PL=/tmp/int/EFI/OC/Kexts/VoodooI2CHID.kext/Contents/Info.plist
PB=/usr/libexec/PlistBuddy
P=":IOKitPersonalities:VoodooI2CHIDDevice"

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ "$($PB -c "Print ${P}:IOPropertyMatch:compatible" "$PL" 2>/dev/null)" = "PNP0C50" ] || { echo "比對條件不是預期的 compatible=PNP0C50（可能已經改過），停止"; exit 1; }

echo "== 1. 備份原本的 Info.plist"
[ -e /tmp/int/EFI/OC/VoodooI2CHID-Info.plist.orig ] || cp "$PL" /tmp/int/EFI/OC/VoodooI2CHID-Info.plist.orig
cp "$PL" "$HERE/VoodooI2CHID-Info.plist.orig"; chown kaoru:staff "$HERE/VoodooI2CHID-Info.plist.orig"
echo "  ESP：EFI/OC/VoodooI2CHID-Info.plist.orig；本機：$HERE/VoodooI2CHID-Info.plist.orig"

echo "== 2. 改比對條件"
$PB -c "Delete ${P}:IOPropertyMatch:compatible" -c "Add ${P}:IOPropertyMatch:IOName string PIXA3854" "$PL"
plutil -lint "$PL"
echo "  IOPropertyMatch.IOName = $($PB -c "Print ${P}:IOPropertyMatch:IOName" "$PL")"
diff <(plutil -convert xml1 -o - "$HERE/VoodooI2CHID-Info.plist.orig") <(plutil -convert xml1 -o - "$PL") || true
echo ""
echo "完成。重開機。"
