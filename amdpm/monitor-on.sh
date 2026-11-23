#!/bin/bash
# 啟用 AMDRyzenCPUPowerManagement [39] + SMCAMDProcessor [40]（只為了看溫度/頻率），同時停用 AMDCState [42]
# （兩者都呼叫 pmKextRegister，xnu 重複註冊會 panic）。只改這三個 Enabled。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/amdpm/monitor-on.sh'
# 還原（macOS）：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1121e /tmp/int/EFI/OC/config.plist'
# 還原（CachyOS）：sudo cp /boot/EFI/OC/config.plist.bak-1121e /boot/EFI/OC/config.plist
set -euo pipefail
OC=${OC:-/tmp/int/EFI/OC}; P=$OC/config.plist; PB=/usr/libexec/PlistBuddy; TAG=1121e
[ -n "${SIM:-}" ] || [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -n "${SIM:-}" ] || mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
chk() { [ "$($PB -c "Print :Kernel:Add:$1:BundlePath" "$P")" = "$2" ] || { echo "Kernel.Add[$1] 不是 $2，停止（沒有改任何東西）"; exit 1; }; }
chk 39 AMDRyzenCPUPowerManagement.kext; chk 40 SMCAMDProcessor.kext; chk 42 AMDCState.kext
for k in AMDRyzenCPUPowerManagement SMCAMDProcessor; do [ -n "${SIM:-}" ] || [ -f "$OC/Kexts/$k.kext/Contents/MacOS/$k" ] || { echo "ESP 上找不到 $k.kext，停止"; exit 1; }; done
if [ -e "$P.bak-${TAG}" ]; then cmp -s "$P" "$P.bak-${TAG}" || { echo "bak-${TAG} 已存在且不同，停止"; exit 1; }; fi
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
[ -n "${SIM:-}" ] || { cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"; chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"; }
$PB -c "Set :Kernel:Add:39:Enabled true" -c "Set :Kernel:Add:40:Enabled true" -c "Set :Kernel:Add:42:Enabled false" "$P"
plutil -lint "$P"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo "完成（備份 config.plist.bak-${TAG}）。[39][40] 啟用、[42] AMDCState 停用。重開機。"
