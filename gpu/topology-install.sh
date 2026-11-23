#!/bin/bash
# 換上「拓撲表改成 FW13 760M 實測值」的 PhxBringup binary（gpu/topology-patch.py 產生，只改 __TEXT,__const 裡 10 bytes）。
#   - 只換 EFI/OC/Kexts/PhxBringup.kext/Contents/MacOS/PhxBringup；Info.plist（IOPCIMatch 含 0x15bf1002）和 config.plist 都不動。
#   - 原本的整個 kext 先備份成 EFI/OC/PhxBringup.kext.v040（不在 Kexts/ 裡，不會被載入）。
#   - 這一步還不會讓一般 App 用 GPU；phxboot 的允許清單（all_apps）是確認拓撲生效後的下一步。
#
# 用法（一行）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/gpu/topology-install.sh'
#
# 出問題才用（現在不要執行）：
#   macOS：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; rm -rf /tmp/int/EFI/OC/Kexts/PhxBringup.kext; cp -R /tmp/int/EFI/OC/PhxBringup.kext.v040 /tmp/int/EFI/OC/Kexts/PhxBringup.kext'
#   CachyOS：sudo rm -rf /boot/EFI/OC/Kexts/PhxBringup.kext && sudo cp -r /boot/EFI/OC/PhxBringup.kext.v040 /boot/EFI/OC/Kexts/PhxBringup.kext
#   （GPU 初始化卡住時 phxboot 會自動建立 phxboot-off 退回 CPU 繪製；最壞情況 config.plist.nophx 停用 PhxBringup）
#
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash topology-install.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
OC=$ESP/EFI/OC
K=PhxBringup
DST=$OC/Kexts/$K.kext
BAK=$OC/$K.kext.v040
NEW=$HERE/build/$K
ORIG_SHA=4a88035fd2ead990b8c44b638c9283d579b14d6ba4f0b48d78d6435a3a44a412
NEW_SHA=6c947da7766ebac2adbe6bde1b667bb7d54ab973a842f61f1f8d96b8e717ad5c

if [ "$DRYRUN" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
    mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$NEW" ] || { echo "找不到 ${NEW}（先跑 gpu/topology-patch.py）"; exit 1; }
[ "$(shasum -a 256 "$NEW" | awk '{print $1}')" = "$NEW_SHA" ] || { echo "新 binary 的 sha 不符，停止"; exit 1; }
[ -f "$DST/Contents/MacOS/$K" ] || { echo "ESP 上找不到 $K.kext，停止"; exit 1; }
[ -e "$BAK" ] && { echo "$BAK 已存在，停止（可能已經跑過）"; exit 1; }
CUR=$(shasum -a 256 "$DST/Contents/MacOS/$K" | awk '{print $1}')
[ "$CUR" = "$ORIG_SHA" ] || { echo "ESP 上的 $K 不是 v0.4.0 release 原版（sha ${CUR}），停止"; exit 1; }

echo "== 1. 備份整個 kext"
ditto "$DST" "$BAK"
echo "  → EFI/OC/$K.kext.v040"

echo "== 2. 只換 binary"
cp "$NEW" "$DST/Contents/MacOS/$K"
echo "  舊 sha ${CUR:0:16}…  新 sha $(shasum -a 256 "$DST/Contents/MacOS/$K" | cut -c1-16)…"
echo "  Info.plist 未動：$(cmp -s "$DST/Contents/Info.plist" "$BAK/Contents/Info.plist" && echo 一致 || echo 不一致！)"
echo "  IOPCIMatch：$(/usr/libexec/PlistBuddy -c 'Print :IOKitPersonalities' "$DST/Contents/Info.plist" | grep -o '0x15bf1002' | head -1)"

echo ""
echo "完成。config.plist 沒有改。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
echo "開機後檢查：ioreg -r -c PhxBringup -l -w0 | grep phx-topology ；system_profiler SPDisplaysDataType | grep Chipset"
