#!/bin/bash
# 把 gpu/phxbringup-fw13-build.sh 編出的 FW13 版 PhxBringup（拓撲表＋VCN 解碼介面＋休眠，build 號見 PHX_KEXT_BUILD）換到 ESP 上。
#   - 只換 Contents/MacOS/PhxBringup 這個二進位，Info.plist 沿用 ESP 上原本那份（IOPCIMatch 已含 0x15bf1002）。
#   - 換之前把 ESP 上整個 kext 備份成 EFI/OC/PhxBringup.kext.bak-fw13-<時間>，並在 ~/EFI-backup 另存一份。
#   - config.plist 不動（Kernel.Add [37] 的路徑不變）。
# 用法（一行，ESP 會自動卸載所以要合在一起）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/gpu/phxbringup-install.sh'
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash gpu/phxbringup-install.sh   （不需 sudo，不檢查掛載）
#
# 出問題才用（現在不要執行），腳本最後會印出這次的備份檔名：
#   CachyOS：sudo cp /boot/EFI/OC/PhxBringup.kext.bak-fw13-<時間>/Contents/MacOS/PhxBringup /boot/EFI/OC/Kexts/PhxBringup.kext/Contents/MacOS/PhxBringup
#   macOS 進得去時：同上，把 /boot 換成 /tmp/int（先掛 ESP）
set -u
R=/Users/kaoru/fw13-hackintosh
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
NEW=${NEW:-$R/nullarc-src/v040-fw13/src/phxbringup/build/PhxBringup.kext/Contents/MacOS/PhxBringup}
K=$ESP/EFI/OC/Kexts/PhxBringup.kext
TAG=$(date +%m%d-%H%M%S)
BAK=$ESP/EFI/OC/PhxBringup.kext.bak-fw13-$TAG

if [ "$DRYRUN" != 1 ]; then
  [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
  mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$NEW" ] || { echo "找不到編好的 ${NEW}（先跑 gpu/phxbringup-fw13-build.sh）"; exit 1; }
[ -f "$K/Contents/MacOS/PhxBringup" ] || { echo "ESP 上找不到 ${K}"; exit 1; }
grep -q 'fw13VcnDec' "$NEW" 2>/dev/null || strings "$NEW" | grep -q 'F13D\|fw13' || echo "  （注意：在新二進位裡找不到 fw13 字串，請確認是 build 134）"
OLD_SHA=$(shasum -a 256 "$K/Contents/MacOS/PhxBringup" | cut -c1-16)
NEW_SHA=$(shasum -a 256 "$NEW" | cut -c1-16)
echo "== ESP 上現在：${OLD_SHA}…  新的：${NEW_SHA}…"
[ "$OLD_SHA" = "$NEW_SHA" ] && { echo "已經是這個版本，不用換"; exit 0; }
plutil -lint "$K/Contents/Info.plist" >/dev/null 2>&1 || [ "$DRYRUN" = 1 ] || { echo "ESP 上的 Info.plist 有問題，停止"; exit 1; }
grep -q '0x15bf1002' "$K/Contents/Info.plist" || { echo "ESP 上的 Info.plist 沒有 0x15bf1002，跟預期不同，停止"; exit 1; }

cp -R "$K" "$BAK" || { echo "備份失敗，停止"; exit 1; }
cmp -s "$K/Contents/MacOS/PhxBringup" "$BAK/Contents/MacOS/PhxBringup" || { echo "備份比對失敗，停止"; exit 1; }
echo "  備份 → ${BAK}"
if [ "$DRYRUN" != 1 ]; then
  mkdir -p /Users/kaoru/EFI-backup && cp -R "$K" "/Users/kaoru/EFI-backup/PhxBringup.kext.bak-fw13-$TAG" && echo "  另存 → /Users/kaoru/EFI-backup/PhxBringup.kext.bak-fw13-$TAG"
fi
cp "$NEW" "$K/Contents/MacOS/PhxBringup" || { echo "複製失敗，從備份還原"; cp "$BAK/Contents/MacOS/PhxBringup" "$K/Contents/MacOS/PhxBringup"; exit 1; }
cmp -s "$NEW" "$K/Contents/MacOS/PhxBringup" || { echo "寫入後比對失敗，從備份還原"; cp "$BAK/Contents/MacOS/PhxBringup" "$K/Contents/MacOS/PhxBringup"; exit 1; }
sync
echo "== 完成：ESP 上的 PhxBringup 換成 ${NEW_SHA}…（Info.plist、config.plist 都沒動）"
echo "還原（CachyOS）：sudo cp /boot/EFI/OC/PhxBringup.kext.bak-fw13-${TAG}/Contents/MacOS/PhxBringup /boot/EFI/OC/Kexts/PhxBringup.kext/Contents/MacOS/PhxBringup"
echo "重開機後確認：ioreg -r -c PhxBringup -d 1 | grep phx-build   （要等於 PhxBringup.cpp 裡的 PHX_KEXT_BUILD）"
