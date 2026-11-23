#!/bin/bash
# 把 ESP 上的 OpenCore.efi 換回 RELEASE 版（oc-debug.sh 留下的 OpenCore.efi.release-bak）。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/oc/oc-release.sh'
set -euo pipefail
OC=/tmp/int/EFI/OC
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$OC/OpenCore.efi.release-bak" ] || { echo "找不到 OpenCore.efi.release-bak"; exit 1; }
cp "$OC/OpenCore.efi.release-bak" "$OC/OpenCore.efi"
cmp "$OC/OpenCore.efi" "$OC/OpenCore.efi.release-bak" && echo "已換回 RELEASE 版。重開機後生效。"
