#!/bin/bash
# 安裝「螢幕關閉時 VBL 不停」版 PhxAccel（= hidpi1 原始碼 + vblFire 不因螢幕變暗而停止），重建 Auxiliary KC。
#   原因：螢幕關閉時 vblFire 直接 return 且不再排程，VBL 從此停掉；IOAccelDisplayPipe 等 VBL 來結束待處理的畫面交換，
#   WindowServer 主執行緒卡在 IOAcceleratorFamily2，40 秒後被看門狗結束（2026-11-22 05:07，hidpi1 版一樣會）。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/phxaccel-port/vblfix-install.sh
# 還原（退回 hidpi1）：sudo bash /Users/kaoru/fw13-hackintosh/phxaccel-port/hidpi2-restore.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NEW="$HERE/build/PhxAccel.kext"
CUR=/Library/Extensions/PhxAccel.kext
WANT=8938cdb4898377ed

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$NEW/Contents/MacOS/PhxAccel" ] || { echo "找不到編譯好的 ${NEW}"; exit 1; }
[ "$(shasum -a 256 "$NEW/Contents/MacOS/PhxAccel" | cut -c1-16)" = "$WANT" ] || { echo "編譯結果的 sha 不是 ${WANT}，停止"; exit 1; }
codesign --verify --strict "$NEW" || { echo "簽章驗證失敗，停止"; exit 1; }
[ -f "$HERE/backup/PhxAccel-hidpi1.kext/Contents/MacOS/PhxAccel" ] || { echo "沒有 hidpi1 備份，停止"; exit 1; }

rm -rf "$CUR"
ditto "$NEW" "$CUR"
chown -R root:wheel "$CUR"; chmod -R go-w "$CUR"
cmp "$NEW/Contents/MacOS/PhxAccel" "$CUR/Contents/MacOS/PhxAccel" && echo "已複製"
BK=/Users/Shared/gpu/backup /Users/Shared/gpu/kinst.sh
echo "已安裝 VBL 修正版 PhxAccel。重開機後生效（重開一次就好，phxboot-off 沒有建立）。"
