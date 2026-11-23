#!/bin/bash
# 加入 SSDT-ALSOFF.aml：只在 macOS 下隱藏環境光感測器（\_SB.I2CA.ECS2），減少 VoodooI2C 輪詢。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/acpi/alsoff.sh'
# 還原：sudo cp /tmp/int/EFI/OC/config.plist.bak-1119h /tmp/int/EFI/OC/config.plist
#       （CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1119h /boot/EFI/OC/config.plist）
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1119h
AML=SSDT-ALSOFF.aml

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$HERE/${AML}" ] || { echo "找不到 ${AML}"; exit 1; }
if $PB -c "Print :ACPI:Add" "$P" | grep -q "Path = ${AML}"; then echo "config 裡已經有 ${AML}，停止"; exit 1; fi
if [ -e "$P.bak-${TAG}" ]; then
    cmp -s "$P" "$P.bak-${TAG}" || { echo "config.plist.bak-${TAG} 已存在且內容不同，停止"; exit 1; }
fi

echo "== 1. 備份"
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
cmp "$P" "$P.bak-${TAG}" && echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"

echo "== 2. 放入 ${AML} 並加到 ACPI.Add 最後"
cp "$HERE/${AML}" "$OC/ACPI/${AML}"
N=$($PB -c "Print :ACPI:Add" "$P" | grep -c "Path = ")
$PB -c "Add :ACPI:Add:${N} dict" \
    -c "Add :ACPI:Add:${N}:Comment string Hide EC ambient light sensor ECS2 from macOS (VoodooI2C polling)" \
    -c "Add :ACPI:Add:${N}:Enabled bool true" \
    -c "Add :ACPI:Add:${N}:Path string ${AML}" "$P"
echo "  [${N}] ${AML}"

echo "== 檢查"
plutil -lint "$P"
echo "  Kernel.Add[37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（未動）"
echo "== 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
