#!/bin/bash
# 讓 AMDCState 改用 C3（讀 port 0x415）：在 boot-args 加上 amdcst=3。只改 boot-args 這一個字串。
# 依據：CachyOS 基準量測中 cpu0 大部分閒置時間在 C3（163 s，C2 只有 22 s），封裝功耗約 5.5 W。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/cstate/c3.sh'
# 還原（macOS）：sudo cp /tmp/int/EFI/OC/config.plist.bak-1121d /tmp/int/EFI/OC/config.plist
# 還原（CachyOS）：sudo cp /boot/EFI/OC/config.plist.bak-1121d /boot/EFI/OC/config.plist
set -euo pipefail
OC=/tmp/int/EFI/OC; P=$OC/config.plist; PB=/usr/libexec/PlistBuddy; TAG=1121d
NV=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
CUR=$($PB -c "Print $NV" "$P")
case " $CUR " in *" amdcst="*) echo "boot-args 已經有 amdcst：$CUR"; exit 1;; esac
if [ -e "$P.bak-${TAG}" ]; then cmp -s "$P" "$P.bak-${TAG}" || { echo "bak-${TAG} 已存在且不同，停止"; exit 1; }; fi
[ -e "$P.bak-${TAG}" ] || cp "$P" "$P.bak-${TAG}"
mkdir -p /Users/kaoru/EFI-backup && cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}" && chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
$PB -c "Set $NV ${CUR} amdcst=3" "$P"
plutil -lint "$P"
echo "新的 boot-args：$($PB -c "Print $NV" "$P")"
echo "完成（備份 config.plist.bak-${TAG}）。重開機。"
