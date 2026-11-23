#!/bin/bash
# 在 ESP 上的 VoodooHDA_BL.kext 加 OSBundleRequired = Root，讓它在開機最早階段載入，
# 搶在系統 IOAudioFamily（由 AppleUSBAudio 帶入）之前註冊 IOAudio* 類別。
# 代價：系統 IOAudioFamily 與 AppleUSBAudio 之後會因類別重複而載入失敗（USB 音訊可能不能用）。
# 用法：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/audio/voodoohda-root.sh'
# 還原：sudo cp /tmp/int/EFI/OC/config.plist.bak-1119i /tmp/int/EFI/OC/config.plist   （停用 VoodooHDA）
#       CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1119i /boot/EFI/OC/config.plist
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PL=/tmp/int/EFI/OC/Kexts/VoodooHDA_BL.kext/Contents/Info.plist
PB=/usr/libexec/PlistBuddy

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
[ -f "$PL" ] || { echo "找不到 ESP 上的 VoodooHDA_BL.kext"; exit 1; }
cmp -s "$PL" "$HERE/dl/x/VoodooHDA_BL.kext/Contents/Info.plist" || { echo "ESP 上的 Info.plist 跟下載的原檔不同，停止"; exit 1; }
$PB -c "Print :OSBundleRequired" "$PL" >/dev/null 2>&1 && { echo "已經有 OSBundleRequired，停止"; exit 1; }

echo "== 1. 備份原本的 Info.plist"
cp "$PL" "$HERE/VoodooHDA_BL-Info.plist.orig"
chown kaoru:staff "$HERE/VoodooHDA_BL-Info.plist.orig"
echo "  $HERE/VoodooHDA_BL-Info.plist.orig"

echo "== 2. 加入 OSBundleRequired = Root"
$PB -c "Add :OSBundleRequired string Root" "$PL"
plutil -lint "$PL"
echo "  OSBundleRequired = $($PB -c 'Print :OSBundleRequired' "$PL")"
diff <(plutil -convert xml1 -o - "$HERE/VoodooHDA_BL-Info.plist.orig") <(plutil -convert xml1 -o - "$PL") || true
echo ""
echo "完成。重開機。"
