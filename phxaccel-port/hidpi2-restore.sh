#!/bin/bash
# 退回 hidpi2 之前的 PhxAccel（第一輪 HiDPI 移植版，sha 3277b0cb…，2026-11-21 存成 backup/PhxAccel-hidpi1.kext）並重建 Auxiliary KC。
# （hidpi-restore.sh 則是退回更早、還沒做任何 HiDPI 移植的版本。）
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/phxaccel-port/hidpi2-restore.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BK="$HERE/backup/PhxAccel-hidpi1.kext"
CUR=/Library/Extensions/PhxAccel.kext
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$BK/Contents/MacOS/PhxAccel" ] || { echo "找不到備份 ${BK}"; exit 1; }
[ "$(shasum -a 256 "$BK/Contents/MacOS/PhxAccel" | cut -c1-16)" = "3277b0cba6147493" ] || { echo "備份的 sha 不對，停止"; exit 1; }
rm -rf "$CUR"
ditto "$BK" "$CUR"
chown -R root:wheel "$CUR"; chmod -R go-w "$CUR"
BK=/Users/Shared/gpu/backup /Users/Shared/gpu/kinst.sh
echo "已退回 hidpi1 版 PhxAccel。重開機後生效。"
