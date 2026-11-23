#!/bin/bash
# 在「SMU 時脈已限制、閒置約 10 W」的新基準下重測 AMDCState：啟用 [42] AMDCState（amdcst=3 → 閒置時讀 port 0x415 進 C3/CC6），
# 停用 [39] AMDRyzenCPUPowerManagement + [40] SMCAMDProcessor（兩者都呼叫 pmKextRegister，不能同時開，重複註冊會 panic）。
# 只改這三個 Enabled。上次測 C-state（2026-11-21 16:16）時封裝是 33 W、被 SMU 時脈問題蓋過，所以「C-state 沒用」的結論要重驗。
# 副作用：AMD Power Gadget 沒有資料、SMC 溫度 key（TC0P）消失；風扇由 EC 控制，不受影響。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/cstate/cstate-on.sh'
# 還原（macOS）：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1122a /tmp/int/EFI/OC/config.plist'
# 還原（CachyOS）：sudo cp /boot/EFI/OC/config.plist.bak-1122a /boot/EFI/OC/config.plist
set -euo pipefail
OC=${OC:-/tmp/int/EFI/OC}; P=$OC/config.plist; PB=/usr/libexec/PlistBuddy; TAG=1122a
[ -n "${SIM:-}" ] || [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -n "${SIM:-}" ] || mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
chk() { [ "$($PB -c "Print :Kernel:Add:$1:BundlePath" "$P")" = "$2" ] || { echo "Kernel.Add[$1] 不是 $2，停止（沒有改任何東西）"; exit 1; }; }
chk 39 AMDRyzenCPUPowerManagement.kext; chk 40 SMCAMDProcessor.kext; chk 42 AMDCState.kext
[ -f "$OC/Kexts/AMDCState.kext/Contents/MacOS/AMDCState" ] || { echo "ESP 上找不到 AMDCState.kext，停止"; exit 1; }
nvram boot-args 2>/dev/null | grep -q 'amdcst=3' || echo "（注意：boot-args 沒有 amdcst=3，AMDCState 會用預設模式）"
if [ -e "$P.bak-${TAG}" ]; then cmp -s "$P" "$P.bak-${TAG}" || { echo "bak-${TAG} 已存在且不同，停止"; exit 1; }; fi
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
[ -n "${SIM:-}" ] || { cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"; chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"; }
$PB -c "Set :Kernel:Add:39:Enabled false" -c "Set :Kernel:Add:40:Enabled false" -c "Set :Kernel:Add:42:Enabled true" "$P"
plutil -lint "$P"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo "完成（備份 config.plist.bak-${TAG}）。[39][40] 停用、[42] AMDCState 啟用。重開機。"
