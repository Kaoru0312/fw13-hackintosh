#!/bin/bash
# 換上自己編的 SimpleMtkBtPatcher（PR flxxxxddd/SimpleMtkBtFw#3，修 Tahoe 上 MT7922 BLE HID 配對卡在 wait-for-phy / LE_READY_WAIT_FOR_LENGTH），
# 並在 boot-args 加 -smbtlefix 啟用修正。
#   - 編譯：bt/build-patcher.sh → bt/build/SimpleMtkBtPatcher.kext（版本字串 1.1.0-lefix）
#   - ESP 上原本的 1.1.0 會先備份成 EFI/OC/SimpleMtkBtPatcher.kext.v110（不在 Kexts/ 裡，不會被載入）
#   - Kernel.Add 編號不動（[46] SimpleMtkBtPatcher 原地換 binary）
#   - 沒有 -smbtlefix 時，新 binary 的行為跟 1.1.0 一樣（新的攔截點只在有這個參數時才掛上）
#
# 用法（一行）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/bt/patcher-lefix.sh'
#
# 出問題才用（現在不要執行）：
#   只關掉修正（保留新 binary）：還原 config → macOS：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1121j /tmp/int/EFI/OC/config.plist'
#                               CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1121j /boot/EFI/OC/config.plist
#   完全換回 1.1.0（CachyOS）：sudo rm -rf /boot/EFI/OC/Kexts/SimpleMtkBtPatcher.kext && sudo cp -r /boot/EFI/OC/SimpleMtkBtPatcher.kext.v110 /boot/EFI/OC/Kexts/SimpleMtkBtPatcher.kext && sudo cp /boot/EFI/OC/config.plist.bak-1121j /boot/EFI/OC/config.plist
#
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash patcher-lefix.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
OC=$ESP/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1121j
K=SimpleMtkBtPatcher
NEW=$HERE/build/$K.kext
KEY=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"
ARG=-smbtlefix

if [ "$DRYRUN" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
    mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$P" ] || { echo "找不到 $P"; exit 1; }
[ -f "$NEW/Contents/MacOS/$K" ] || { echo "找不到編好的 ${NEW}（先跑 bt/build-patcher.sh）"; exit 1; }
strings "$NEW/Contents/MacOS/$K" | grep -qx -- "$ARG" || { echo "新 binary 裡沒有 ${ARG}，不是 PR #3 的版本，停止"; exit 1; }
[ -d "$OC/Kexts/$K.kext" ] || { echo "ESP 上沒有 $K.kext（藍牙腳本 bt/mtk-bt.sh 還沒跑？），停止"; exit 1; }
$PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = $K.kext" || { echo "config 裡沒有 ${K}，停止"; exit 1; }
OLD=$($PB -c "Print $KEY" "$P")
case " $OLD " in *" $ARG "*) echo "boot-args 已經有 ${ARG}，停止"; exit 1;; esac
[ -e "$P.bak-${TAG}" ] && { echo "config.plist.bak-${TAG} 已存在，停止（可能已經跑過）"; exit 1; }

echo "== 1. 備份"
cp "$P" "$P.bak-${TAG}"
[ -e "$OC/$K.kext.v110" ] || ditto "$OC/Kexts/$K.kext" "$OC/$K.kext.v110"
echo "  ESP 上原本的 kext → EFI/OC/$K.kext.v110（$($PB -c 'Print :CFBundleShortVersionString' "$OC/$K.kext.v110/Contents/Info.plist")）"
if [ "$DRYRUN" != 1 ]; then
    mkdir -p /Users/kaoru/EFI-backup
    cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"
else
    echo "  config.plist.bak-${TAG}"
fi

echo "== 2. 換上新 binary"
rm -rf "$OC/Kexts/$K.kext"
ditto "$NEW" "$OC/Kexts/$K.kext"
echo "  $K.kext $($PB -c 'Print :CFBundleShortVersionString' "$OC/Kexts/$K.kext/Contents/Info.plist")  sha256 $(shasum -a 256 "$OC/Kexts/$K.kext/Contents/MacOS/$K" | cut -c1-16)…"

echo "== 3. boot-args 加上 $ARG"
$PB -c "Set $KEY ${OLD} ${ARG}" "$P"

echo "== 檢查"
plutil -lint "$P"
echo "  新 boot-args：$($PB -c "Print $KEY" "$P")"
echo "== config 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
echo "開機後檢查：ioreg -r -c IOResources -l -w0 | grep -o '\"SimpleMtkBtLE[A-Za-z]*\" = [0-9]*' ；再配對一次 MX Master 3S。"
