#!/bin/bash
# 加入 AirportMtkWlan.kext（MediaTek Wi-Fi），Kernel.Add 最後一項，MinKernel 25.0.0 / MaxKernel 25.99.99（只在 Tahoe 載入）。
#   - 來源：kevin8717/TongFang-7840HS-Hackintosh（2026-11-08），上游 Arxusion/AirportMtkWlan 2.0.0 + 他們 4 處修正
#     （beacon 有效位、teardown/deep-sleep 順序、15 秒背景掃描節流）。他們在 macOS 26.7.2（Darwin 25.6.0）的 MT7921 上可用。
#   - IOPCIMatch 含 0x061614c3 = FW13 的 RZ616（ioreg pci14c3,616）。連結的是系統內建 IO80211Family / IOSkywalkFamily / corecapture，
#     他們的 config 沒有額外的 kernel patch 或 Block。
#   - binary SHA-256：2d6fc08bcb930d7d01d76e6f9b553e9839b855bd04b38b0a2c2a0b2efaaf383c（腳本會檢查）
#   - 本機的 NullEthernet（假 en0，給 iCloud 用）不動；Wi-Fi 會是另一個介面。
#
# 用法（一行）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/wifi/airportmtk.sh'
#
# 出問題才用（現在不要執行）：
#   macOS：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1121h /tmp/int/EFI/OC/config.plist'
#   CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1121h /boot/EFI/OC/config.plist
#   （開機卡住或 panic 時用；kext 資料夾留在 ESP 上無害）
#
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash airportmtk.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
OC=$ESP/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1121h
K=AirportMtkWlan
SRC=$HERE/dl/${K}.kext
SHA=2d6fc08bcb930d7d01d76e6f9b553e9839b855bd04b38b0a2c2a0b2efaaf383c

if [ "$DRYRUN" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
    mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$P" ] || { echo "找不到 $P"; exit 1; }
[ "$(shasum -a 256 "$SRC/Contents/MacOS/${K}" | awk '{print $1}')" = "$SHA" ] || { echo "${K} binary 的 SHA-256 不符，停止"; exit 1; }
$PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = ${K}.kext" && { echo "config 裡已經有 ${K}，停止"; exit 1; }
[ -e "$P.bak-${TAG}" ] && { echo "config.plist.bak-${TAG} 已存在，停止（可能已經跑過）"; exit 1; }

echo "== 1. 備份"
cp "$P" "$P.bak-${TAG}"
if [ "$DRYRUN" != 1 ]; then
    mkdir -p /Users/kaoru/EFI-backup
    cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"
else
    echo "  config.plist.bak-${TAG}"
fi

echo "== 2. 放入 ${K}.kext 並加到 Kernel.Add 最後"
rm -rf "$OC/Kexts/${K}.kext"
ditto "$SRC" "$OC/Kexts/${K}.kext"
N=$($PB -c "Print :Kernel:Add" "$P" | grep -c "BundlePath")
$PB -c "Add :Kernel:Add:${N} dict" \
    -c "Add :Kernel:Add:${N}:Arch string x86_64" \
    -c "Add :Kernel:Add:${N}:BundlePath string ${K}.kext" \
    -c "Add :Kernel:Add:${N}:Comment string AirportMtkWlan 2.0.0 (TongFang build) RZ616 Wi-Fi" \
    -c "Add :Kernel:Add:${N}:Enabled bool true" \
    -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/${K}" \
    -c "Add :Kernel:Add:${N}:MaxKernel string 25.99.99" \
    -c "Add :Kernel:Add:${N}:MinKernel string 25.0.0" \
    -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"
echo "  [${N}] ${K}"

echo "== 檢查"
plutil -lint "$P"
echo "  [37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（未動）"
echo "== 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
echo "開機後檢查：kextstat | grep -i mtk ；ifconfig | grep -A3 '^en' ；選單列有沒有 Wi-Fi 圖示。"
