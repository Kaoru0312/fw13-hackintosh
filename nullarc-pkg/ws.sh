#!/bin/bash
# 讓 GPU 接管畫面（nullarc --windowserver），先在 ESP 放一份救援用 config。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash ~kaoru/fw13-hackintosh/nullarc-pkg/ws.sh'
# 救援（CachyOS）：sudo cp /boot/EFI/OC/config.plist.nophx /boot/EFI/OC/config.plist
#   = 目前的 config，但 PhxBringup 停用、boot-args 加 -phxfboff：GPU 不初始化、PhxAMDFB 不接管，回到 CPU 繪製。
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OC=/tmp/int/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
NV=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ "$($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")" = "PhxBringup.kext" ] || { echo "Kernel.Add[37] 不是 PhxBringup，停止"; exit 1; }

echo "== 1. 救援用 config：config.plist.nophx"
cp "$P" "$OC/config.plist.nophx"
$PB -c "Set :Kernel:Add:37:Enabled false" "$OC/config.plist.nophx"
cur=$($PB -c "Print ${NV}" "$OC/config.plist.nophx")
case " ${cur} " in *" -phxfboff "*) ;; *) $PB -c "Set ${NV} ${cur} -phxfboff" "$OC/config.plist.nophx" ;; esac
plutil -lint "$OC/config.plist.nophx"
mkdir -p /Users/kaoru/EFI-backup && cp "$OC/config.plist.nophx" /Users/kaoru/EFI-backup/ && chown kaoru:staff /Users/kaoru/EFI-backup/config.plist.nophx
echo "  與目前 config 的差異："
diff <(plutil -convert xml1 -o - "$P") <(plutil -convert xml1 -o - "$OC/config.plist.nophx") || true
cmp -s "$P" "$OC/config.plist.nophx" && { echo "救援 config 與目前相同，停止"; exit 1; }
echo "  目前使用中的 config.plist 沒有修改"

echo "== 2. 安裝 nullarc（--windowserver）"
bash "$HERE/install.sh" --windowserver

echo ""
echo "== 狀態"
ls -l /Users/Shared/gpu/phxboot-m2
cmp "$HERE/gpu/phxboot.sh" /Users/Shared/gpu/phxboot.sh && echo "  phxboot.sh 是只讓 WindowServer 用 GPU 的版本"
cmp "$HERE/Library/Extensions/PhxAccel.kext/Contents/Info.plist" /Library/Extensions/PhxAccel.kext/Contents/Info.plist && echo "  PhxAccel 是 NMXAccel 與 PhxFB 都認得 15bf 的版本"
echo ""
echo "完成。確認已開啟自動登入，然後重開機兩次（第一次只設定，第二次才接管畫面）。"
