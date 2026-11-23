#!/bin/bash
# 加入 VoodooHDA_BL.kext（CloverHackyColor v3.7.1-alpha，可由 OpenCore 直接載入），Kernel.Add 最後一項。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/audio/voodoohda.sh'
# 還原：sudo cp /tmp/int/EFI/OC/config.plist.bak-1119i /tmp/int/EFI/OC/config.plist
#       （CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1119i /boot/EFI/OC/config.plist）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1119i
K=VoodooHDA_BL

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$HERE/dl/x/${K}.kext/Contents/MacOS/${K}" ] || { echo "找不到 ${K}.kext"; exit 1; }
if $PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = ${K}.kext"; then echo "config 裡已經有 ${K}，停止"; exit 1; fi
if [ -e "$P.bak-${TAG}" ]; then
    cmp -s "$P" "$P.bak-${TAG}" || { echo "config.plist.bak-${TAG} 已存在且內容不同，停止"; exit 1; }
fi

echo "== 1. 備份"
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
cmp "$P" "$P.bak-${TAG}" && echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"

echo "== 2. 放入 ${K}.kext 並加到 Kernel.Add 最後"
rm -rf "$OC/Kexts/${K}.kext"
ditto "$HERE/dl/x/${K}.kext" "$OC/Kexts/${K}.kext"
N=$($PB -c "Print :Kernel:Add" "$P" | grep -c "BundlePath")
$PB -c "Add :Kernel:Add:${N} dict" \
    -c "Add :Kernel:Add:${N}:Arch string x86_64" \
    -c "Add :Kernel:Add:${N}:BundlePath string ${K}.kext" \
    -c "Add :Kernel:Add:${N}:Comment string VoodooHDA 3.7.1-alpha (CloverHackyColor, bootloader build)" \
    -c "Add :Kernel:Add:${N}:Enabled bool true" \
    -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/${K}" \
    -c "Add :Kernel:Add:${N}:MaxKernel string" \
    -c "Add :Kernel:Add:${N}:MinKernel string" \
    -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"
echo "  [${N}] ${K}"

echo "== 檢查"
plutil -lint "$P"
echo "  [37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（未動）"
echo "== 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
