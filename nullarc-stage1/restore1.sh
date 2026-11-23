#!/bin/bash
# 還原 nullarc 階段 1（macOS 用）：先掛載 ESP 到 /tmp/int，再執行  sudo bash restore1.sh
# config.plist 換回 bak-$TAG（預設 1119d），PhxBringup.kext 換回舊版。
# 在 CachyOS 還原（ESP 掛在 /boot）只需要一行：
#   sudo cp /boot/EFI/OC/config.plist.bak-$TAG /boot/EFI/OC/config.plist
set -euo pipefail
OC=/tmp/int/EFI/OC
TAG=${TAG:-1119d}
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$OC/config.plist.bak-$TAG" ] || { echo "找不到 config.plist.bak-$TAG"; exit 1; }
cp "$OC/config.plist.bak-$TAG" "$OC/config.plist"
if [ -d "$OC/Kexts-disabled/PhxBringup.kext.old" ]; then
    rm -rf "$OC/Kexts/PhxBringup.kext"
    mv "$OC/Kexts-disabled/PhxBringup.kext.old" "$OC/Kexts/PhxBringup.kext"
fi
plutil -lint "$OC/config.plist"
echo "已還原。卸載 ESP 後重開機。"
