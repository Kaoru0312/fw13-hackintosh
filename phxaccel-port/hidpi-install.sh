#!/bin/bash
# 安裝 HiDPI 版 PhxAccel.kext（原始碼版 + IOFBScalerInfo / 詳細時序支援）到 /Library/Extensions 並重建 Auxiliary KC。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/phxaccel-port/hidpi-install.sh
# 還原：sudo bash /Users/kaoru/fw13-hackintosh/phxaccel-port/hidpi-restore.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
NEW="$HERE/build/PhxAccel.kext"
CUR=/Library/Extensions/PhxAccel.kext
BKDIR="$HERE/backup"

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$NEW/Contents/MacOS/PhxAccel" ] || { echo "找不到編譯好的 PhxAccel.kext"; exit 1; }
[ -d "$CUR" ] || { echo "系統裡沒有 PhxAccel.kext，停止"; exit 1; }
codesign --verify --strict "$NEW" || { echo "新 kext 簽章驗證失敗，停止"; exit 1; }

echo "== 1. 備份目前的 PhxAccel.kext"
mkdir -p "$BKDIR"
if [ ! -d "$BKDIR/PhxAccel.kext" ]; then
    ditto "$CUR" "$BKDIR/PhxAccel.kext"
    echo "  $BKDIR/PhxAccel.kext"
else
    echo "  已有備份，保留不覆蓋：$BKDIR/PhxAccel.kext"
fi
chown -R kaoru:staff "$BKDIR"

echo "== 2. 換上 HiDPI 版"
rm -rf "$CUR"
ditto "$NEW" "$CUR"
chown -R root:wheel "$CUR"; chmod -R go-w "$CUR"
cmp "$NEW/Contents/MacOS/PhxAccel" "$CUR/Contents/MacOS/PhxAccel" && echo "  已複製"

echo "== 3. 重建 Auxiliary kernel collection"
BK=/Users/Shared/gpu/backup /Users/Shared/gpu/kinst.sh
echo ""
echo "完成。重開機後到「系統設定 → 顯示器」打開「顯示所有解析度」看看。"
