#!/bin/bash
# 閒置封裝功耗量測（只讀，不改任何設定）。每 5 秒記一次 AMDPMProbe 的封裝功耗、C0、CPU 溫度，最後算平均／最小／最大／中位數，
# 並記錄量測條件（開機時間、電源、GPU 接管、GFX 時鐘閘控狀態、GFXCLK、CPU 前幾名）。
#   - 前 60 秒當暖機，不算進統計（腳本剛啟動、終端機剛畫完畫面）。
#   - 結果寫到 /Users/kaoru/fw13-hackintosh/power/idle-<時間>.txt
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/power/idle-measure.sh [總秒數，預設 360]
# 跑的時候不要碰觸控板和鍵盤，Claude app 縮到 Dock、AMD Power Gadget 和系統設定關掉。
set -u
DUR=${1:-360}; WARM=60
G=/Users/Shared/gpu
PHXCTL=$G/phxctl/phxctl
SMC=/tmp/smcdump
OUT=/Users/kaoru/fw13-hackintosh/power/idle-$(date +%m%d-%H%M%S).txt

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行（讀 GPU 暫存器和 SMU 要 root）"; exit 1; }
pgrep -x "AMD Power Gadget" >/dev/null && { echo "AMD Power Gadget 開著，請先關掉（它會把閒置功耗拉高很多）"; exit 1; }
pgrep -x "System Settings" >/dev/null && { echo "系統設定開著，請先關掉（顯示器頁面曾吃 100% CPU）"; exit 1; }
[ -n "$(ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{print $2}')" ] || { echo "讀不到 AMDPMProbe 的 PackagePowerMilliWatt，停止"; exit 1; }
[ -x "$SMC" ] || cc -O2 -framework IOKit -framework CoreFoundation /Users/kaoru/fw13-hackintosh/tools/smcdump.c -o "$SMC"

exec > >(tee "$OUT") 2>&1
pw() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{print $2}'; }
c0() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"C0PermilleAvg"/{print $2}'; }

echo "== $(date '+%F %T') 閒置功耗量測 ${DUR} 秒（前 ${WARM} 秒暖機不計）"
echo "  uptime: $(uptime | sed 's/^ *//')"
echo "  電源: $(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")；$(pmset -g batt | grep -o '[0-9]*%;[^;]*' | head -1)"
echo "  GPU 接管: $([ -e $G/phxboot-off ] && echo '關（phxboot-off 存在）' || echo 開)；phxboot 最後: $(grep '^done' /var/log/phxboot.log | tail -1)"
echo "  GFX 時鐘閘控: $([ -x $G/gpucg.sh ] && $G/gpucg.sh status || echo '沒安裝 gpucg.sh')"
echo "  GFXCLK: $("$PHXCTL" smu 0x17 0 2>&1 | grep -o 'out 0x[0-9a-f]*' | head -1)（0x320 = 800 MHz）"
echo "  CPU 前 8 名:"; ps -Aceo pcpu,comm -r | head -9 | sed 's/^/    /'
echo "== 取樣"
start=$(date +%s); vals=()
while [ $(( $(date +%s) - start )) -lt "$DUR" ]; do
    el=$(( $(date +%s) - start )); p=$(pw)
    tag=""; if [ "$el" -lt "$WARM" ]; then tag=" (暖機)"; else vals+=("$p"); fi
    printf "  %s  +%3ds  %6s mW  C0=%s‰  %s%s\n" "$(date +%T)" "$el" "$p" "$(c0)" "$($SMC TC0P)" "$tag"
    sleep 5
done
echo "== 統計（暖機後 ${#vals[@]} 筆）"
printf '%s\n' "${vals[@]}" | sort -n | awk '{a[NR]=$1; s+=$1} END {if (NR==0) {print "  沒有資料"; exit}
  m=(NR%2)?a[(NR+1)/2]:(a[NR/2]+a[NR/2+1])/2;
  printf "  平均 %.2f W、中位數 %.2f W、最小 %.2f W、最大 %.2f W\n", s/NR/1000, m/1000, a[1]/1000, a[NR]/1000}'
echo "  CPU 前 8 名（結束時）:"; ps -Aceo pcpu,comm -r | head -9 | sed 's/^/    /'
echo "結果存在 ${OUT}"
