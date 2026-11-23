#!/bin/bash
# 停用 AMD 電源管理 kext（Kernel.Add[39] AMDRyzenCPUPowerManagement、[40] SMCAMDProcessor，檔案留在 ESP），
# 並刪除 phxboot 的關閉開關，讓 GPU 恢復接管畫面。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/amdpm/amdpm-off.sh'
# 還原（重新啟用 kext）：sudo cp /tmp/int/EFI/OC/config.plist.bak-1119g /tmp/int/EFI/OC/config.plist
set -euo pipefail
OC=/tmp/int/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1119g

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:39:BundlePath' "$P")" = "AMDRyzenCPUPowerManagement.kext" ] || { echo "Kernel.Add[39] 不是 AMDRyzenCPUPowerManagement，停止"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:40:BundlePath' "$P")" = "SMCAMDProcessor.kext" ] || { echo "Kernel.Add[40] 不是 SMCAMDProcessor，停止"; exit 1; }
if [ -e "$P.bak-${TAG}" ]; then
    cmp -s "$P" "$P.bak-${TAG}" || { echo "config.plist.bak-${TAG} 已存在且內容不同，停止"; exit 1; }
fi

echo "== 1. 備份"
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
cmp "$P" "$P.bak-${TAG}" && echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"

echo "== 2. 停用 [39] [40]"
$PB -c "Set :Kernel:Add:39:Enabled false" -c "Set :Kernel:Add:40:Enabled false" "$P"
plutil -lint "$P"
echo "  [39] $($PB -c 'Print :Kernel:Add:39:BundlePath' "$P") Enabled=$($PB -c 'Print :Kernel:Add:39:Enabled' "$P")"
echo "  [40] $($PB -c 'Print :Kernel:Add:40:BundlePath' "$P") Enabled=$($PB -c 'Print :Kernel:Add:40:Enabled' "$P")"
echo "  與備份的差異："
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true

echo "== 3. 恢復 GPU"
rm -f /Users/Shared/gpu/phxboot-off /var/db/phxboot.pending
ls /Users/Shared/gpu | grep -E "off|m2" || true
[ -e /Users/Shared/gpu/phxboot-m2 ] && echo "  phxboot-m2 存在：第一次重開初始化 GPU 並設定接管，第二次重開接管畫面"
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機兩次。"
