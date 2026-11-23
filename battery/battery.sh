#!/bin/bash
# 啟用電池顯示：加入 ECEnabler.kext（Kernel.Add 最後一項），啟用 SMCBatteryManager（Kernel.Add[19]）。
# 用法：ESP 掛在 /tmp/int 時執行  sudo bash battery.sh
# 還原：sudo cp /tmp/int/EFI/OC/config.plist.bak-1119e /tmp/int/EFI/OC/config.plist
#       （CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1119e /boot/EFI/OC/config.plist）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1119e
SRC="$HERE/dl/x/ECEnabler.kext"

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$SRC/Contents/MacOS/ECEnabler" ] || { echo "找不到 ECEnabler.kext"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:19:BundlePath' "$P")" = "SMCBatteryManager.kext" ] || { echo "Kernel.Add[19] 不是 SMCBatteryManager，停止"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:0:BundlePath' "$P")" = "Lilu.kext" ] || { echo "Kernel.Add[0] 不是 Lilu，停止"; exit 1; }
if [ -e "$P.bak-${TAG}" ]; then
    # 上一次執行在備份之後中斷：備份與目前 config 相同就沿用，不同就停止
    cmp -s "$P" "$P.bak-${TAG}" || { echo "config.plist.bak-${TAG} 已存在且與目前 config 不同，停止以免覆蓋"; exit 1; }
    echo "  沿用已存在且內容相同的 config.plist.bak-${TAG}"
fi
if $PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = ECEnabler.kext"; then echo "config 裡已經有 ECEnabler，停止"; exit 1; fi

echo "== 1. 備份"
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
cmp "$P" "$P.bak-${TAG}" && echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"

echo "== 2. 放入 ECEnabler.kext"
rm -rf "$OC/Kexts/ECEnabler.kext"
ditto "$SRC" "$OC/Kexts/ECEnabler.kext"

echo "== 3. Kernel.Add 最後新增 ECEnabler"
N=$($PB -c "Print :Kernel:Add" "$P" | grep -c "BundlePath")
$PB -c "Add :Kernel:Add:${N} dict" \
    -c "Add :Kernel:Add:${N}:Arch string Any" \
    -c "Add :Kernel:Add:${N}:BundlePath string ECEnabler.kext" \
    -c "Add :Kernel:Add:${N}:Comment string EC fields wider than 8 bits (battery)" \
    -c "Add :Kernel:Add:${N}:Enabled bool true" \
    -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/ECEnabler" \
    -c "Add :Kernel:Add:${N}:MaxKernel string" \
    -c "Add :Kernel:Add:${N}:MinKernel string" \
    -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"

echo "== 4. 啟用 SMCBatteryManager"
$PB -c "Set :Kernel:Add:19:Enabled true" "$P"

echo "== 檢查"
plutil -lint "$P"
echo "  [19] $($PB -c 'Print :Kernel:Add:19:BundlePath' "$P") Enabled=$($PB -c 'Print :Kernel:Add:19:Enabled' "$P")"
echo "  [${N}] $($PB -c "Print :Kernel:Add:${N}:BundlePath" "$P") Enabled=$($PB -c "Print :Kernel:Add:${N}:Enabled" "$P")"
echo "  [37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（編號未變）"
echo "== 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
