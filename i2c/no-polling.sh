#!/bin/bash
# 從 boot-args 拿掉 -vi2c-force-polling，讓觸控板改回 GPIO 中斷模式（EC 裝置已不被 VoodooI2C 接管）。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/i2c/no-polling.sh'
# 還原（游標又卡住時）：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1121a /tmp/int/EFI/OC/config.plist'
#   CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1121a /boot/EFI/OC/config.plist
set -euo pipefail
P=/tmp/int/EFI/OC/config.plist
PB=/usr/libexec/PlistBuddy
NV=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"
TAG=1121a
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
cur=$($PB -c "Print ${NV}" "$P")
case " ${cur} " in *" -vi2c-force-polling "*) ;; *) echo "boot-args 裡沒有 -vi2c-force-polling，停止"; exit 1 ;; esac
if [ -e "$P.bak-${TAG}" ]; then cmp -s "$P" "$P.bak-${TAG}" || { echo "bak-${TAG} 已存在且不同，停止"; exit 1; }; fi
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
new=$(echo " ${cur} " | sed 's/ -vi2c-force-polling / /; s/^ //; s/ $//')
$PB -c "Set ${NV} ${new}" "$P"
plutil -lint "$P"
echo "  舊：${cur}"
echo "  新：$($PB -c "Print ${NV}" "$P")"
echo "完成（備份 config.plist.bak-${TAG}）。重開機。"
