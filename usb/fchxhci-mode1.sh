#!/bin/bash
# 在 boot-args 加 fchxhcimode=1：FCHXHCIFix 只在 USB 控制器真的有事件（USBSTS.EINT）時才叫 AppleUSBXHCIPCI 起來處理。
#   - 原因（2026-11-21 DTrace 量到）：FCHXHCIFix 1.0.2 預設是 mode 2（每次輪詢都轉送），每 1 ms 一次 → 每秒 1,000 次
#     AppleUSBXHCI::interruptOccurred/ioInterrupt，裡面大量 MMIO 讀取（ml_io_read），佔 kernel_task 大部分時間（約 35% 一顆核心）。
#   - mode 1：輪詢執行緒照樣每 1 ms 讀一次 USBSTS，但只有 EINT 有設時才轉送（從反組譯確認：
#     EINT 有設 → 清掉並轉送；沒設 → mode≥2 才轉送）。
#   - 風險：如果這台的 EINT 不可靠，外接 USB 鍵盤/滑鼠可能又回到「幾秒才動一下」。內建鍵盤（PS/2）和觸控板（I2C）不受影響。
#
# 用法（一行）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/usb/fchxhci-mode1.sh'
#
# 出問題才用（現在不要執行）：
#   macOS：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1121g /tmp/int/EFI/OC/config.plist'
#   CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1121g /boot/EFI/OC/config.plist
#
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash fchxhci-mode1.sh
set -euo pipefail
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
P=$ESP/EFI/OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1121g
KEY=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"
ARG=fchxhcimode=1

if [ "$DRYRUN" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
    mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$P" ] || { echo "找不到 $P"; exit 1; }
OLD=$($PB -c "Print $KEY" "$P")
case " $OLD " in *" fchxhcimode="*) echo "boot-args 已經有 fchxhcimode，停止：$OLD"; exit 1;; esac
[ -e "$P.bak-${TAG}" ] && { echo "config.plist.bak-${TAG} 已存在，停止（可能已經跑過）"; exit 1; }
$PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = FCHXHCIFix.kext" || { echo "config 裡沒有 FCHXHCIFix，停止"; exit 1; }

echo "== 1. 備份"
cp "$P" "$P.bak-${TAG}"
if [ "$DRYRUN" != 1 ]; then
    mkdir -p /Users/kaoru/EFI-backup
    cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"
else
    echo "  config.plist.bak-${TAG}"
fi

echo "== 2. boot-args 加上 ${ARG}"
$PB -c "Set $KEY ${OLD} ${ARG}" "$P"

echo "== 檢查"
plutil -lint "$P"
echo "  舊：$OLD"
echo "  新：$($PB -c "Print $KEY" "$P")"
echo "  [37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（未動）"
echo "== 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
echo "開機後檢查：ioreg -l -w0 | grep -o '\"FCHXHCIFix-state\" = \"[^\"]*\"' | head -1   （應顯示 mode 1，forwards 遠少於 polls）"
