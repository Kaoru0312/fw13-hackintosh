#!/bin/bash
# 硬解階段 0：在 CachyOS 收集 VCN 4.0.2（影片解碼器）的韌體與 Linux 初始化資訊，寫到 /boot（ESP，macOS 讀得到）。只讀，不改任何設定。
#   /boot/fw13-vcn/vcn_4_0_2.bin        韌體（linux-firmware，解壓後）
#   /boot/fw13-vcn/info.txt             kernel / linux-firmware 版本、amdgpu 韌體版本表、dmesg 裡的 VCN 訊息、IP discovery 的 VCN 部分
# 用法（CachyOS 預設 shell 是 fish，用 bash 執行）：
#   sudo bash ~/fw13-hackintosh/tools/cachyos-vcn-collect.sh
set -u
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
OUT=/boot/fw13-vcn
mkdir -p "$OUT"
FW=""
for f in /usr/lib/firmware/amdgpu/vcn_4_0_2.bin.zst /usr/lib/firmware/amdgpu/vcn_4_0_2.bin.xz /usr/lib/firmware/amdgpu/vcn_4_0_2.bin; do
    [ -f "$f" ] && { FW=$f; break; }
done
[ -n "$FW" ] || { echo "找不到 vcn_4_0_2.bin（ls /usr/lib/firmware/amdgpu/ | grep vcn 看看）"; ls /usr/lib/firmware/amdgpu/ | grep -i vcn; exit 1; }
case "$FW" in
    *.zst) zstd -dc "$FW" > "$OUT/vcn_4_0_2.bin" ;;
    *.xz)  xz -dc "$FW" > "$OUT/vcn_4_0_2.bin" ;;
    *)     cp "$FW" "$OUT/vcn_4_0_2.bin" ;;
esac
{
    echo "== $(date '+%F %T')  kernel $(uname -r)"
    echo "== 來源 $FW"
    sha256sum "$OUT/vcn_4_0_2.bin"
    echo "== linux-firmware 套件"; pacman -Q linux-firmware linux-firmware-amdgpu 2>/dev/null
    echo "== amdgpu_firmware_info（debugfs）"
    for d in /sys/kernel/debug/dri/*/amdgpu_firmware_info; do [ -f "$d" ] && { echo "-- $d"; cat "$d"; }; done
    echo "== dmesg（vcn / jpeg / psp / smu）"
    dmesg | grep -iE 'vcn|jpeg|psp|smu|vcn_4' | head -80
    echo "== VCN 電源狀態（amdgpu_pm_info，debugfs）"
    for d in /sys/kernel/debug/dri/*/amdgpu_pm_info; do [ -f "$d" ] && { echo "-- $d"; cat "$d"; }; done
    echo "== 影片解碼能力（vainfo，若有安裝）"
    command -v vainfo >/dev/null && vainfo 2>&1 | head -40
} > "$OUT/info.txt" 2>&1
ls -l "$OUT"
echo "完成。回 macOS 後跟 Claude 說「VCN 韌體抓好了」。"
