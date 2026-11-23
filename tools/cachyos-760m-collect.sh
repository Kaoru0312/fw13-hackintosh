#!/bin/bash
# 在 CachyOS 抓 760M 的真實拓撲（CU / RB 遮罩），給 macOS 端的 PhxBringup 用。只讀，不改任何設定。
#   - 用 nullarc 的 tools/linux-profile/collect.c（複製在 tools/collect-760m.c）：只發 AMDGPU_INFO ioctl，
#     不碰暫存器、不載韌體、不改裝置設定。
#   - 結果寫到 /boot（ESP，macOS 讀得到）：
#       /boot/fw13-760m.json   拓撲（JSON）
#       /boot/fw13-ip.txt      IP block 資訊（stderr）
#       /boot/fw13-760m-info.txt  lspci、kernel、amdgpu 版本等對照資訊
# 用法（CachyOS 預設 shell 是 fish，所以用 bash 執行）：
#   sudo bash ~/fw13-hackintosh/tools/cachyos-760m-collect.sh
set -u
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/collect-760m.c"
[ -f "$SRC" ] || { echo "找不到 $SRC"; exit 1; }
command -v cc >/dev/null || { echo "沒有 cc。請先：sudo pacman -S --needed base-devel"; exit 1; }

INC=$(pkg-config --cflags libdrm 2>/dev/null)
[ -z "$INC" ] && [ -f /usr/include/libdrm/amdgpu_drm.h ] && INC="-I/usr/include/libdrm"
[ -z "$INC" ] && { echo "找不到 libdrm 標頭（amdgpu_drm.h）。請先：sudo pacman -S --needed libdrm pkgconf"; exit 1; }

DEV=""
for d in /dev/dri/renderD*; do
    drv=$(basename "$(readlink -f /sys/class/drm/$(basename "$d")/device/driver 2>/dev/null)" 2>/dev/null)
    [ "$drv" = "amdgpu" ] && { DEV=$d; break; }
done
[ -n "$DEV" ] || { echo "找不到 amdgpu 的 render node"; ls -l /dev/dri; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "== 編譯 collect（${INC}）"
cc -std=c11 -Wall -Wextra -Werror $INC "$SRC" -o "$TMP/collect" || { echo "編譯失敗"; exit 1; }

echo "== 讀取 $DEV"
"$TMP/collect" "$DEV" > "$TMP/760m.json" 2> "$TMP/ip.txt" || { echo "collect 失敗："; cat "$TMP/ip.txt"; exit 1; }
cp "$TMP/760m.json" /boot/fw13-760m.json
cp "$TMP/ip.txt" /boot/fw13-ip.txt
{
    echo "== $(date '+%F %T')  kernel $(uname -r)"
    echo "== render node $DEV"
    lspci -nnk -d 1002: 2>/dev/null
    echo "== amdgpu firmware / gfx"
    cat /sys/class/drm/card*/device/vbios_version 2>/dev/null
    grep -H . /sys/class/drm/card*/device/{revision,subsystem_vendor,subsystem_device} 2>/dev/null
} > /boot/fw13-760m-info.txt 2>&1

echo ""
cat /boot/fw13-760m.json
echo ""
echo "完成。已寫到 /boot/fw13-760m.json、/boot/fw13-ip.txt、/boot/fw13-760m-info.txt。回 macOS 後跟 Claude 說「拓撲抓好了」。"
