#!/bin/bash
# 暫時把 ESP 上的 OpenCore.efi 換成 1.0.8 DEBUG 版（記錄每個 kext 的注入過程）。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/oc/oc-debug.sh'
# 換回：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/oc/oc-release.sh'
# CachyOS 換回：sudo cp /boot/EFI/OC/OpenCore.efi.release-bak /boot/EFI/OC/OpenCore.efi
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC
DBG="$HERE/dbg/X64/EFI/OC/OpenCore.efi"

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$DBG" ] || { echo "找不到 DEBUG 版 OpenCore.efi"; exit 1; }
cmp -s "$OC/OpenCore.efi" "$DBG" && { echo "ESP 上已經是 DEBUG 版，不用再換"; exit 0; }

echo "== 1. 備份 RELEASE 版"
if [ -e "$OC/OpenCore.efi.release-bak" ]; then
    cmp -s "$OC/OpenCore.efi" "$OC/OpenCore.efi.release-bak" || { echo "OpenCore.efi.release-bak 已存在且內容不同，停止"; exit 1; }
else
    cp "$OC/OpenCore.efi" "$OC/OpenCore.efi.release-bak"
fi
mkdir -p /Users/kaoru/EFI-backup && cp "$OC/OpenCore.efi" /Users/kaoru/EFI-backup/OpenCore.efi.release-bak && chown kaoru:staff /Users/kaoru/EFI-backup/OpenCore.efi.release-bak
cmp "$OC/OpenCore.efi" "$OC/OpenCore.efi.release-bak" && echo "  OpenCore.efi.release-bak（ESP 與 ~/EFI-backup 各一份）"

echo "== 2. 換上 DEBUG 版"
cp "$DBG" "$OC/OpenCore.efi"
cmp "$DBG" "$OC/OpenCore.efi" && echo "  完成（$(stat -f %z "$OC/OpenCore.efi") bytes）"
echo ""
echo "完成。重開機一次（開機會顯示較多文字、慢幾秒），進到桌面後再請 Claude 讀記錄。"
