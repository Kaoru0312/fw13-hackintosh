#!/bin/bash
# nullarc 階段 1：只讓 PhxBringup.kext 由 OpenCore 載入，不執行 install.sh。
# 用法：先掛載 ESP 到 /tmp/int，再執行  sudo bash stage1.sh
# 會做的事：
#   1. 備份整個 EFI/OC 到 ~kaoru/EFI-backup/OC-$TAG（預設 1119d），另存 config.plist.bak-$TAG
#   2. 舊的 PhxBringup.kext 移到 EFI/OC/Kexts-disabled/（不刪除）
#   3. 放入 release v0.4.0 的 PhxBringup.kext（只改了 IOPCIMatch，加上 0x15bf1002）
#   4. config.plist：Kernel.Add[37] PhxBringup 啟用；boot-args 加上 amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta phxdebug=1
# 還原：sudo bash restore1.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
NV=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"
TAG=${TAG:-1119d}
BK=/Users/kaoru/EFI-backup/OC-$TAG
ADD="amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta phxdebug=1"

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$HERE/PhxBringup.kext/Contents/MacOS/PhxBringup" ] || { echo "找不到改好的 PhxBringup.kext"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")" = "PhxBringup.kext" ] || { echo "Kernel.Add[37] 不是 PhxBringup，停止"; exit 1; }
[ -e "$BK" ] && { echo "$BK 已存在，為避免覆蓋舊備份，停止"; exit 1; }

echo "== 1. 備份"
mkdir -p "$(dirname "$BK")"
ditto "$OC" "$BK"
cp "$P" "$P.bak-$TAG"
cmp "$P" "$BK/config.plist" && cmp "$P" "$P.bak-$TAG" && echo "  備份完成：$BK 與 config.plist.bak-$TAG"
chown -R kaoru:staff "$(dirname "$BK")"

echo "== 2. 舊 PhxBringup 移到 Kexts-disabled"
mkdir -p "$OC/Kexts-disabled"
if [ -d "$OC/Kexts/PhxBringup.kext" ]; then
    rm -rf "$OC/Kexts-disabled/PhxBringup.kext.old"
    mv "$OC/Kexts/PhxBringup.kext" "$OC/Kexts-disabled/PhxBringup.kext.old"
fi

echo "== 3. 放入新 PhxBringup"
ditto "$HERE/PhxBringup.kext" "$OC/Kexts/PhxBringup.kext"
$PB -c "Print :IOKitPersonalities:PhxBringup:IOPCIMatch" "$OC/Kexts/PhxBringup.kext/Contents/Info.plist"

echo "== 4. 修改 config.plist"
$PB -c "Set :Kernel:Add:37:Enabled true" "$P"
cur=$($PB -c "Print $NV" "$P")
case " $cur " in *" phxdebug=1 "*) echo "  boot-args 已含 phxdebug=1，不重複加入" ;; *) $PB -c "Set $NV $cur $ADD" "$P" ;; esac

echo "== 檢查"
plutil -lint "$P"
echo "  boot-args: $($PB -c "Print $NV" "$P")"
echo "  Kernel.Add[37]: $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P") Enabled=$($PB -c 'Print :Kernel:Add:37:Enabled' "$P")"
echo "== 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-$TAG") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
