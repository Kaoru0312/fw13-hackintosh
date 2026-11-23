#!/bin/bash
# 闔上／打開螢幕時是誰在耗電：每 ~10 秒記 lid 狀態、封裝功耗、WindowServer 合成幀數增量（debug.nvaccel_iop_ok）、
# VBL 增量，以及 CPU 前 6 名程序（top 取第二次取樣才準）。只讀。
# 用法：bash tools/lid-proc-log.sh <總秒數> <輸出檔>
set -u
DUR=${1:-480}
OUT=${2:-/Users/kaoru/fw13-hackintosh/display/lid-proc.txt}
exec > >(tee "$OUT") 2>&1
end=$(( $(date +%s) + DUR ))
f0=$(sysctl -n debug.nvaccel_iop_ok 2>/dev/null || echo 0); v0=$(sysctl -n debug.phxfb_vbl_n); t0=$(date +%s)
while [ "$(date +%s)" -lt "$end" ]; do
    tp=$(top -l 2 -s 5 -n 6 -o cpu -stats cpu,command 2>/dev/null | awk '/^%CPU/{n++; next} n==2 && NF{printf "%s %s | ", $1, $2}')
    f1=$(sysctl -n debug.nvaccel_iop_ok 2>/dev/null || echo 0); v1=$(sysctl -n debug.phxfb_vbl_n); t1=$(date +%s)
    dt=$(( t1 - t0 )); [ $dt -lt 1 ] && dt=1
    lid=$(ioreg -r -k AppleClamshellState -d1 -w0 | awk -F'= ' '/"AppleClamshellState"/{print ($2=="Yes")?"closed":"open"; exit}')
    p=$(ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{printf "%.1f", $2/1000}')
    printf "%s %-6s pkg %5sW  frames/s %4s  vbl/s %4s  %s\n" "$(date +%T)" "$lid" "$p" $(( (f1 - f0) / dt )) $(( (v1 - v0) / dt )) "$tp"
    f0=$f1; v0=$v1; t0=$t1
    sleep 4
done
