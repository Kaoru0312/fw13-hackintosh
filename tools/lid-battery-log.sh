#!/bin/bash
# 用電池時每 10 秒記錄：螢幕是否闔上、整機放電功率（電池電壓 × 電流）、封裝功耗（AMDPMProbe）、C0、CPU 溫度、電量。只讀。
#   - ioreg 的 Amperage 是無號 64 位元，放電時要減 2^64 才是負值（HANDOFF §9b）；InstantAmperage 剛拔充電器時會停在舊值一陣子。
# 用法：bash tools/lid-battery-log.sh <總秒數> <輸出檔>
set -u
DUR=${1:-360}
OUT=${2:-/Users/kaoru/fw13-hackintosh/battery-lid.txt}
SMC=/tmp/smcdump
[ -x "$SMC" ] || cc -O2 -framework IOKit -framework CoreFoundation /Users/kaoru/fw13-hackintosh/tools/smcdump.c -o "$SMC"
exec > >(tee "$OUT") 2>&1
echo "time      lid     batt_W   pkg_W  C0‰  temp   %   source"
end=$(( $(date +%s) + DUR ))
while [ "$(date +%s)" -lt "$end" ]; do
    b=$(ioreg -r -c AppleSmartBattery -l -w0)
    v=$(echo "$b" | awk -F'= ' '/"Voltage" =/{print $2; exit}')
    a=$(echo "$b" | awk -F'= ' '/"InstantAmperage" =/{print $2; exit}')
    [ -z "$a" ] && a=$(echo "$b" | awk -F'= ' '/"Amperage" =/{print $2; exit}')
    pct=$(pmset -g batt | grep -o '[0-9]*%' | head -1 | tr -d '%')
    w=$(/usr/bin/python3 -I -c "import sys; v=int(sys.argv[1]); a=int(sys.argv[2]); a=a-2**64 if a>2**63 else a; print(f'{v*a/1e6:7.2f}')" "${v:-0}" "${a:-0}")
    lid=$(ioreg -r -k AppleClamshellState -d1 -w0 | awk -F'= ' '/"AppleClamshellState"/{print ($2=="Yes")?"closed":"open"; exit}')
    p=$(ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{printf "%.2f", $2/1000}')
    c=$(ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"C0PermilleAvg"/{print $2}')
    t=$($SMC TC0P | sed 's/TC0P=//; s/ //g')
    src=$(pmset -g batt | head -1 | sed "s/.*'\(.*\)'.*/\1/")
    printf "%s  %-6s  %7s  %6s  %3s  %5s  %3s  %s\n" "$(date +%T)" "${lid:-?}" "$w" "$p" "$c" "$t" "$pct" "$src"
    sleep 10
done
