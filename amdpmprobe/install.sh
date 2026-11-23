#!/bin/bash
# 把 AMDPMProbe.kext（唯讀）加到 OpenCore：Kernel.Add 最後一項。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/amdpmprobe/install.sh'
# 還原：sudo cp /tmp/int/EFI/OC/config.plist.bak-1121b /tmp/int/EFI/OC/config.plist
#       （CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1121b /boot/EFI/OC/config.plist）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC; P=$OC/config.plist; PB=/usr/libexec/PlistBuddy; TAG=1121b; K=AMDPMProbe
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$HERE/build/${K}.kext/Contents/MacOS/${K}" ] || { echo "找不到 build/${K}.kext"; exit 1; }
if $PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = ${K}.kext"; then echo "config 裡已經有 ${K}，只更新 kext 檔案"; rm -rf "$OC/Kexts/${K}.kext"; ditto "$HERE/build/${K}.kext" "$OC/Kexts/${K}.kext"; echo 完成; exit 0; fi
if [ -e "$P.bak-${TAG}" ]; then cmp -s "$P" "$P.bak-${TAG}" || { echo "bak-${TAG} 已存在且不同，停止"; exit 1; }; fi
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
rm -rf "$OC/Kexts/${K}.kext"; ditto "$HERE/build/${K}.kext" "$OC/Kexts/${K}.kext"
N=$($PB -c "Print :Kernel:Add" "$P" | grep -c "BundlePath")
$PB -c "Add :Kernel:Add:${N} dict" -c "Add :Kernel:Add:${N}:Arch string x86_64" -c "Add :Kernel:Add:${N}:BundlePath string ${K}.kext" \
    -c "Add :Kernel:Add:${N}:Comment string read-only AMD PM MSR probe (home-made, stage 0)" -c "Add :Kernel:Add:${N}:Enabled bool true" \
    -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/${K}" -c "Add :Kernel:Add:${N}:MaxKernel string" \
    -c "Add :Kernel:Add:${N}:MinKernel string" -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"
plutil -lint "$P"
echo "  [${N}] ${K}；[37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（未動）"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") | head -5 || true
echo "完成（備份 config.plist.bak-${TAG}）。重開機。"
