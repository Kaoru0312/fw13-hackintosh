#!/bin/bash
# VoodooHDA_BL 改用 PCI ID 比對 AZAL（1022:15e3），參考機械革命無界 14 Pro EFI（同一支 3.7.1 二進位、同一顆 AZAL，在 26.7.3 可出聲）。
#   - 原本 Info.plist 用 IONameMatch=HDAS，但 FW13 的節點叫 AZAL → 推測就是「OpenCore 注入成功但開機沒比對」的原因（未驗證）。
#   - 只改這一個變數：刪 IONameMatch、加 IOPCIPrimaryMatch=0x15e31022。HDMI personality、音量相關設定都不動。
#   - kext 先從 dl/x 原檔重新複製一份，順便清掉之前 voodoohda-root.sh 加的 OSBundleRequired=Root。
#   - config：VoodooHDA_BL 已在 Kernel.Add 就只設 Enabled=true；不在就加到最後一項（不改動既有編號）。
#
# 用法（一行，ESP 會自動卸載所以要合在一起）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/audio/voodoohda-pcimatch.sh'
#
# 出問題才用（現在不要執行）：
#   macOS：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1121f /tmp/int/EFI/OC/config.plist'
#   CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1121f /boot/EFI/OC/config.plist
#   （還原 config 後 VoodooHDA 回到原本狀態；kext 資料夾留在 ESP 上無害）
#
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash voodoohda-pcimatch.sh   （不需 sudo，不檢查掛載，不寫 ~/EFI-backup）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
OC=$ESP/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1121f
K=VoodooHDA_BL
SRC=$HERE/dl/x/${K}.kext
KPL=$OC/Kexts/${K}.kext/Contents/Info.plist
PCIID=0x15e31022

if [ "$DRYRUN" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
    mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$P" ] || { echo "找不到 $P"; exit 1; }
[ -f "$SRC/Contents/MacOS/${K}" ] || { echo "找不到 $SRC"; exit 1; }
if [ -e "$P.bak-${TAG}" ]; then
    cmp -s "$P" "$P.bak-${TAG}" || { echo "config.plist.bak-${TAG} 已存在且內容不同，停止（可能已經跑過）"; exit 1; }
fi

echo "== 1. 備份"
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
if [ -f "$KPL" ] && [ ! -e "$OC/${K}-Info.plist.bak-${TAG}" ]; then
    cp "$KPL" "$OC/${K}-Info.plist.bak-${TAG}"
    echo "  ESP 上原本的 kext Info.plist → EFI/OC/${K}-Info.plist.bak-${TAG}"
fi
if [ "$DRYRUN" != 1 ]; then
    mkdir -p /Users/kaoru/EFI-backup
    cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
fi
cmp "$P" "$P.bak-${TAG}" && echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"

echo "== 2. 重新放入原版 ${K}.kext，改比對條件"
rm -rf "$OC/Kexts/${K}.kext"
ditto "$SRC" "$OC/Kexts/${K}.kext"
$PB -c "Delete :IOKitPersonalities:VoodooHDA:IONameMatch" \
    -c "Add :IOKitPersonalities:VoodooHDA:IOPCIPrimaryMatch string ${PCIID}" "$KPL"
plutil -lint "$KPL"
diff <(plutil -convert xml1 -o - "$SRC/Contents/Info.plist") <(plutil -convert xml1 -o - "$KPL") || true

echo "== 3. config.plist Kernel.Add"
N=$($PB -c "Print :Kernel:Add" "$P" | grep -c "BundlePath")
IDX=""
for ((i=0; i<N; i++)); do
    [ "$($PB -c "Print :Kernel:Add:${i}:BundlePath" "$P")" = "${K}.kext" ] && { IDX=$i; break; }
done
if [ -n "$IDX" ]; then
    $PB -c "Set :Kernel:Add:${IDX}:Enabled true" "$P"
    echo "  [${IDX}] ${K} 已存在 → Enabled=true"
else
    $PB -c "Add :Kernel:Add:${N} dict" \
        -c "Add :Kernel:Add:${N}:Arch string x86_64" \
        -c "Add :Kernel:Add:${N}:BundlePath string ${K}.kext" \
        -c "Add :Kernel:Add:${N}:Comment string VoodooHDA 3.7.1 (PCI match AZAL 1022:15e3)" \
        -c "Add :Kernel:Add:${N}:Enabled bool true" \
        -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/${K}" \
        -c "Add :Kernel:Add:${N}:MaxKernel string" \
        -c "Add :Kernel:Add:${N}:MinKernel string" \
        -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"
    echo "  [${N}] ${K}（新增在最後）"
fi

echo "== 檢查"
plutil -lint "$P"
echo "  [37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（未動）"
$PB -c "Print :OSBundleRequired" "$KPL" >/dev/null 2>&1 && { echo "  !! kext 還有 OSBundleRequired，不應該發生"; exit 1; }
echo "  kext 沒有 OSBundleRequired（OK）"
echo "== config 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
echo "開機後檢查：ioreg -r -c VoodooHDADevice -d 1 | head -20 ；系統設定 → 聲音 有沒有輸出裝置。"
