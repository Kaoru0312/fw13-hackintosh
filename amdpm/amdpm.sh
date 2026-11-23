#!/bin/bash
# 加入 AMD CPU 電源管理：AMDRyzenCPUPowerManagement.kext + SMCAMDProcessor.kext（Kernel.Add 最後兩項，依此順序）。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/amdpm/amdpm.sh'
# 還原：sudo cp /tmp/int/EFI/OC/config.plist.bak-1119f /tmp/int/EFI/OC/config.plist
#       （CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1119f /boot/EFI/OC/config.plist）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1119f

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
for k in AMDRyzenCPUPowerManagement SMCAMDProcessor; do
    [ -f "$HERE/dl/x/${k}.kext/Contents/MacOS/${k}" ] || { echo "找不到 ${k}.kext"; exit 1; }
    if $PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = ${k}.kext"; then echo "config 裡已經有 ${k}，停止"; exit 1; fi
done
[ "$($PB -c 'Print :Kernel:Add:0:BundlePath' "$P")" = "Lilu.kext" ] || { echo "Kernel.Add[0] 不是 Lilu，停止"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:5:BundlePath' "$P")" = "VirtualSMC.kext" ] || { echo "Kernel.Add[5] 不是 VirtualSMC，停止"; exit 1; }
if [ -e "$P.bak-${TAG}" ]; then
    cmp -s "$P" "$P.bak-${TAG}" || { echo "config.plist.bak-${TAG} 已存在且內容不同，停止"; exit 1; }
fi

echo "== 1. 備份"
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
cmp "$P" "$P.bak-${TAG}" && echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"

echo "== 2. 放入 kext 並加到 Kernel.Add 最後"
for k in AMDRyzenCPUPowerManagement SMCAMDProcessor; do
    rm -rf "$OC/Kexts/${k}.kext"
    ditto "$HERE/dl/x/${k}.kext" "$OC/Kexts/${k}.kext"
    N=$($PB -c "Print :Kernel:Add" "$P" | grep -c "BundlePath")
    $PB -c "Add :Kernel:Add:${N} dict" \
        -c "Add :Kernel:Add:${N}:Arch string x86_64" \
        -c "Add :Kernel:Add:${N}:BundlePath string ${k}.kext" \
        -c "Add :Kernel:Add:${N}:Comment string AMD CPU power management (trulyspinach 0.7.2f1)" \
        -c "Add :Kernel:Add:${N}:Enabled bool true" \
        -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/${k}" \
        -c "Add :Kernel:Add:${N}:MaxKernel string" \
        -c "Add :Kernel:Add:${N}:MinKernel string" \
        -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"
    echo "  [${N}] ${k}"
done

echo "== 檢查"
plutil -lint "$P"
echo "  [37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")、[38] $($PB -c 'Print :Kernel:Add:38:BundlePath' "$P")（編號未變）"
echo "== 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
