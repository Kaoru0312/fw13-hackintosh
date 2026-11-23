#!/bin/bash
# 只更新 ESP 上的 AMDPMProbe.kext（config.plist 不動）。舊版先備份到 EFI/OC/AMDPMProbe.kext.v1。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/amdpmprobe/update.sh'
# 還原（macOS）：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; rm -rf /tmp/int/EFI/OC/Kexts/AMDPMProbe.kext; cp -R /tmp/int/EFI/OC/AMDPMProbe.kext.v1 /tmp/int/EFI/OC/Kexts/AMDPMProbe.kext'
# 還原（CachyOS）：sudo rm -rf /boot/EFI/OC/Kexts/AMDPMProbe.kext && sudo cp -r /boot/EFI/OC/AMDPMProbe.kext.v1 /boot/EFI/OC/Kexts/AMDPMProbe.kext
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC; K=AMDPMProbe
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$HERE/build/${K}.kext/Contents/MacOS/${K}" ] || { echo "找不到 build/${K}.kext"; exit 1; }
[ -d "$OC/Kexts/${K}.kext" ] || { echo "ESP 上沒有 ${K}.kext，請改用 install.sh"; exit 1; }
if [ ! -d "$OC/${K}.kext.v1" ]; then ditto "$OC/Kexts/${K}.kext" "$OC/${K}.kext.v1"; echo "已備份舊版到 EFI/OC/${K}.kext.v1"; else echo "已有 EFI/OC/${K}.kext.v1，保留不覆蓋"; fi
rm -rf "$OC/Kexts/${K}.kext"; ditto "$HERE/build/${K}.kext" "$OC/Kexts/${K}.kext"
cmp "$HERE/build/${K}.kext/Contents/MacOS/${K}" "$OC/Kexts/${K}.kext/Contents/MacOS/${K}" && echo "已更新。重開機。"
