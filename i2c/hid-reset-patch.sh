#!/bin/bash
# 換上自己編的 VoodooI2CHID binary（VoodooI2C 2.9.1 內附版本 a478fd6 + i2c/patches/hid-reset-power-on.patch）：
#   RESET 完成後再送一次 SET_POWER(ON)；RESET 逾時不再放棄初始化（照 Linux i2c-hid）。
#   目標：觸控板偶爾開機後完全沒反應（驅動樹都在）。想法來自 kevin8717/VoodooI2C-htix5288。
#   - 只換 Contents/MacOS/VoodooI2CHID；Info.plist（IOPropertyMatch IOName=PIXA3854）和 config.plist 都不動。
#   - 原本的整個 kext 先備份成 EFI/OC/VoodooI2CHID.kext.orig-1121k（不在 Kexts/ 裡，不會被載入）。
#   - 新 binary 會發布 ioreg 屬性 FW13PostResetPowerOn / FW13PostResetPowerOnRet / FW13ResetTimeouts（在 VoodooI2CHIDDevice 上）。
#
# 用法（一行）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/i2c/hid-reset-patch.sh'
#
# 出問題才用（現在不要執行）：
#   macOS：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; rm -rf /tmp/int/EFI/OC/Kexts/VoodooI2CHID.kext; cp -R /tmp/int/EFI/OC/VoodooI2CHID.kext.orig-1121k /tmp/int/EFI/OC/Kexts/VoodooI2CHID.kext'
#   CachyOS：sudo rm -rf /boot/EFI/OC/Kexts/VoodooI2CHID.kext && sudo cp -r /boot/EFI/OC/VoodooI2CHID.kext.orig-1121k /boot/EFI/OC/Kexts/VoodooI2CHID.kext
#
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash hid-reset-patch.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
OC=$ESP/EFI/OC
K=VoodooI2CHID
DST=$OC/Kexts/$K.kext
BAK=$OC/$K.kext.orig-1121k
NEW=$HERE/build/$K
ORIG_SHA=65975f7018ef10e2f058f46492f52fe49a5e5e2680dc7cf66af12b167f1d7f0a   # VoodooI2C 2.9.1 release 的 VoodooI2CHID

if [ "$DRYRUN" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
    mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$NEW" ] || { echo "找不到編好的 ${NEW}（先跑 i2c/build-hid.sh）"; exit 1; }
strings "$NEW" | grep -q "FW13PostResetPowerOn" || { echo "新 binary 沒有補丁標記，停止"; exit 1; }
[ -f "$DST/Contents/MacOS/$K" ] || { echo "ESP 上找不到 $K.kext，停止"; exit 1; }
[ -e "$BAK" ] && { echo "$BAK 已存在，停止（可能已經跑過）"; exit 1; }
CUR=$(shasum -a 256 "$DST/Contents/MacOS/$K" | awk '{print $1}')
[ "$CUR" = "$ORIG_SHA" ] || { echo "ESP 上的 $K binary 不是 2.9.1 原版（sha ${CUR}），停止"; exit 1; }
/usr/libexec/PlistBuddy -c "Print :IOKitPersonalities" "$DST/Contents/Info.plist" | grep -q "PIXA3854" || echo "  注意：ESP 上的 Info.plist 沒有 PIXA3854 比對（照原樣保留，不處理）"

echo "== 1. 備份整個 kext"
ditto "$DST" "$BAK"
echo "  → EFI/OC/$K.kext.orig-1121k"

echo "== 2. 只換 binary"
cp "$NEW" "$DST/Contents/MacOS/$K"
echo "  舊 sha ${CUR:0:16}…  新 sha $(shasum -a 256 "$DST/Contents/MacOS/$K" | cut -c1-16)…"
echo "  Info.plist 未動：$(cmp -s "$DST/Contents/Info.plist" "$BAK/Contents/Info.plist" && echo 一致 || echo 不一致！)"

echo ""
echo "完成。config.plist 沒有改。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
echo "開機後檢查：ioreg -r -c VoodooI2CHIDDevice -l -w0 | grep -E 'FW13|IOName'"
