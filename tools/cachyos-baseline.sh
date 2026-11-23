#!/bin/bash
# CachyOS 閒置功耗基準（只讀，不改任何設定）。結果同時印出並寫到 /boot/fw13-baseline.txt（ESP，macOS 也讀得到）。
# 用法（先拔充電器、關掉其他程式、開機後閒置 2 分鐘）：
#   sudo bash cachyos-baseline.sh
set -u
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
OUT=/boot/fw13-baseline.txt
exec > >(tee "$OUT") 2>&1
echo "== fw13 CachyOS baseline $(date '+%F %T')  kernel $(uname -r)"
echo "== 亮度 $(cat /sys/class/backlight/*/brightness 2>/dev/null | head -1)/$(cat /sys/class/backlight/*/max_brightness 2>/dev/null | head -1)"
BAT=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
RAPL=$(grep -l '^package' /sys/class/powercap/*/name 2>/dev/null | head -1 | xargs -r dirname)
HW=$(for h in /sys/class/drm/card*/device/hwmon/hwmon*; do [ -e "$h/power1_average" ] || [ -e "$h/power1_input" ] && echo "$h"; done | head -1)
echo "== 電池 ${BAT:-無}  RAPL ${RAPL:-無}  amdgpu hwmon ${HW:-無}"
[ -n "$BAT" ] && echo "   電池狀態 $(cat $BAT/status)"
echo "== amdgpu 參數：gfxoff 相關"
grep -H . /sys/module/amdgpu/parameters/{ppfeaturemask,runpm} 2>/dev/null
echo "== 每 5 秒取樣一次，共 12 次（60 秒）"
printf "%-8s %10s %10s %10s %8s\n" time pkg_W bat_W gpu_W gfxoff
E0=$( [ -n "$RAPL" ] && cat $RAPL/energy_uj ); T0=$(date +%s%N)
for i in $(seq 1 12); do
  sleep 5
  T1=$(date +%s%N); PKG=-; BATW=-; GPU=-; GO=-
  if [ -n "$RAPL" ]; then E1=$(cat $RAPL/energy_uj); PKG=$(awk -v d=$((E1-E0)) -v t=$((T1-T0)) 'BEGIN{ if (d<0) print "wrap"; else printf "%.2f", d*1000/t }'); E0=$E1; fi
  [ -n "$BAT" ] && [ -e $BAT/power_now ] && BATW=$(awk '{printf "%.2f", $1/1e6}' $BAT/power_now)
  [ -n "$BAT" ] && [ ! -e $BAT/power_now ] && BATW=$(awk -v v=$(cat $BAT/voltage_now) -v c=$(cat $BAT/current_now) 'BEGIN{printf "%.2f", v*c/1e12}')
  if [ -n "$HW" ]; then f=$HW/power1_average; [ -e $f ] || f=$HW/power1_input; GPU=$(awk '{printf "%.2f", $1/1e6}' $f); fi
  GO=$(cat /sys/kernel/debug/dri/*/amdgpu_gfxoff_status 2>/dev/null | head -1 | tr -d ' \n')
  printf "%-8s %10s %10s %10s %8s\n" "$(date +%T)" "$PKG" "$BATW" "$GPU" "${GO:--}"
  T0=$T1
done
echo "== gfxoff 狀態代碼：0=GPU 已斷電(GFXOFF) 1=正在離開 2=未斷電 3=正在進入"
echo "== gfxoff 累計（若核心支援）"
cat /sys/kernel/debug/dri/*/amdgpu_gfxoff_residency 2>/dev/null | head -3
echo "== CPU C-state（cpu0）"
for s in /sys/devices/system/cpu/cpu0/cpuidle/state*; do printf "   %-6s %-12s usage=%s time_us=%s\n" "$(basename $s)" "$(cat $s/name)" "$(cat $s/usage)" "$(cat $s/time)"; done
echo "== cpufreq driver: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null)  EPP: $(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)"
echo "== 前 5 名 CPU 使用"
top -bn1 | sed -n '7,12p'
echo "== 完成，已存到 $OUT"
