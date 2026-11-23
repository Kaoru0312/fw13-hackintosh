#!/bin/bash
# 閒置時 kernel_task 在忙什麼、誰一直把 CPU 叫醒。只讀（dtrace / powermetrics 取樣，不改任何設定）。SIP 已關，dtrace 可用。
#   1. powermetrics interrupts：每顆 CPU 每秒的中斷數（IPI / 計時器 / 裝置）
#   2. dtrace profile：kernel_task 佔 CPU 時的 stack（看是哪個 kext）
#   3. dtrace thread_call_invoke：每個 thread_call 回呼被呼叫幾次（kext 計時器）
#   4. dtrace IOTimerEventSource / IOInterruptEventSource：哪個 driver 的計時器、中斷最頻繁
# 結果：/Users/kaoru/fw13-hackintosh/power/wakeups-<時間>.txt
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/power/kernel-wakeups.sh
# 跑之前：關掉 AMD Power Gadget、系統設定，Claude app 縮到 Dock，跑的 75 秒內不要碰電腦（按 Enter 後手就離開）。
set -u
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
OUT=/Users/kaoru/fw13-hackintosh/power/wakeups-$(date +%m%d-%H%M%S).txt
exec > >(tee "$OUT") 2>&1
echo "== $(date '+%F %T')  uptime $(uptime | sed 's/.*up //; s/,.*//')"
echo "== 背景程式"; ps -Ao pcpu,comm | sort -nr | head -8
pgrep -x "AMD Power Gadget" >/dev/null && echo "!! AMD Power Gadget 開著（數字會偏高）"
pgrep -x "System Settings" >/dev/null && echo "!! 系統設定開著（數字會偏高）"
echo "== 封裝功耗 $(ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{print $2}') mW  C0 $(ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"C0PermilleAvg"/{print $2}')‰"

echo; echo "== 0. 等 45 秒讓觸控板輪詢降到閒置速度（50 ms）——這段時間請完全不要碰觸控板和鍵盤"
for i in 45 30 15; do echo "  還有 ${i} 秒"; sleep 15; done
echo; echo "== 1. powermetrics interrupts（5 秒）"
powermetrics -s interrupts -n 1 -i 5000 2>&1 | sed -n '/Interrupt/,$p' | head -60

echo; echo "== 2–4. dtrace（20 秒）"
dtrace -q -Z -x stackframes=12 -n '
profile-997 /pid == 0 && arg0/ { @prof[stack(8)] = count(); }
fbt:mach_kernel:thread_call_enter_delayed*:entry,
fbt:mach_kernel:thread_call_enter1_delayed*:entry { @tc[stack(2)] = count(); }
fbt::*IOTimerEventSource*timeout*:entry { @tes[probefunc, stack(4)] = count(); }
fbt::*IOInterruptEventSource*normalInterruptOccurred*:entry,
fbt::*IOFilterInterruptEventSource*normalInterruptOccurred*:entry,
fbt::*IOFilterInterruptEventSource*disableInterruptOccurred*:entry { @irq[probefunc, stack(3)] = count(); }
tick-20s {
  printf("\n---- kernel_task CPU stack（前 12，997 Hz 取樣；20 秒共約 %d 個取樣/CPU）\n", 997*20);
  trunc(@prof, 12); printa(@prof);
  printf("\n---- thread_call 排程次數（呼叫端 stack）（20 秒，前 25）\n"); trunc(@tc, 25); printa(@tc);
  printf("\n---- IOTimerEventSource（20 秒，前 15）\n"); trunc(@tes, 15); printa(@tes);
  printf("\n---- 中斷事件來源（20 秒，前 15）\n"); trunc(@irq, 15); printa(@irq);
  exit(0);
}' 2>&1
echo; echo "結果存在 ${OUT}"
