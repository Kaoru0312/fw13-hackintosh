#!/bin/bash
# 休眠測試用：停用 Kernel.Add[39] AMDRyzenCPUPowerManagement、[40] SMCAMDProcessor（監看用；[39] 會用 pmKextRegister 掛進 xnu 的 CPU 電源管理，
# 睡眠寫映像時 xnu 會透過它停住其他 CPU）。只能在 hib-test.sh on 之後用：不另做備份，hib-test.sh off 從 bak-hib2 還原整份 config 時會一起打開。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/power/hib-nopm.sh'
set -u
P=/tmp/int/EFI/OC/config.plist
PB=/usr/libexec/PlistBuddy
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f /tmp/int/EFI/OC/config.plist.bak-hib2 ] || { echo "沒有 config.plist.bak-hib2：先跑 hib-test.sh on，停止"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:39:BundlePath' "$P")" = AMDRyzenCPUPowerManagement.kext ] || { echo "Kernel.Add[39] 不是 AMDRyzenCPUPowerManagement，停止"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:40:BundlePath' "$P")" = SMCAMDProcessor.kext ] || { echo "Kernel.Add[40] 不是 SMCAMDProcessor，停止"; exit 1; }
cp "$P" "$P.tmp-nopm"
$PB -c "Set :Kernel:Add:39:Enabled false" -c "Set :Kernel:Add:40:Enabled false" "$P" && plutil -lint "$P" >/dev/null || { echo "失敗，還原"; cp "$P.tmp-nopm" "$P"; exit 1; }
diff <(plutil -p "$P.tmp-nopm") <(plutil -p "$P"); rm -f "$P.tmp-nopm"; sync
echo "✅ [39] [40] 已停用（重開機後生效；AMD Power Gadget 會沒有資料）。hib-test.sh off 會一起還原。"
