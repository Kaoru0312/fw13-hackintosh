#!/bin/bash
# 還原 hidpi-install.sh 之前的 PhxAccel.kext 並重建 Auxiliary KC。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/phxaccel-port/hidpi-restore.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BK="$HERE/backup/PhxAccel.kext"
CUR=/Library/Extensions/PhxAccel.kext
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$BK/Contents/MacOS/PhxAccel" ] || { echo "找不到備份 $BK"; exit 1; }
rm -rf "$CUR"
ditto "$BK" "$CUR"
chown -R root:wheel "$CUR"; chmod -R go-w "$CUR"
BK=/Users/Shared/gpu/backup /Users/Shared/gpu/kinst.sh
echo "已還原原本的 PhxAccel.kext。重開機後生效。"
