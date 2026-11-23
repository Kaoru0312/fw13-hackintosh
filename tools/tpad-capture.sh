#!/bin/bash
# 觸控板狀態快照（只讀）。觸控板失效時執行一次；能用時也執行一次當對照。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/tools/tpad-capture.sh
# 結果：~/fw13-hackintosh/tpad/<時間>-<ok|bad>.txt
set -u
TAG=${1:-}
[ -n "$TAG" ] || { read -r -p "觸控板現在能用嗎？(y/n) " a; [ "$a" = y ] && TAG=ok || TAG=bad; }
D=/Users/kaoru/fw13-hackintosh/tpad; mkdir -p "$D"
O="$D/$(date +%m%d-%H%M%S)-$TAG.txt"
{
echo "== $(date '+%F %T') tag=$TAG  uptime: $(uptime)"
echo "== boot-args: $(sysctl -n kern.bootargs)"
echo "== VoodooI2C 相關 kext"; kmutil showloaded 2>/dev/null | grep -i voodoo
echo "== ioreg：I2C 控制器與觸控板樹"; ioreg -w0 -r -c VoodooI2CControllerDriver -l 2>/dev/null | grep -E '\+-o|"(IOName|name|polling|force-polling|IOInterruptSpecifiers|interrupt)' | head -60
echo "== ioreg：HID 裝置"; ioreg -w0 -r -c VoodooI2CHIDDevice -l 2>/dev/null | grep -E '\+-o|"(IOName|HIDDescriptorAddress|MaxInputReportSize|ReportDescriptor|VendorID|ProductID)' | head -30
echo "== ioreg：觸控事件驅動"; ioreg -w0 -r -c VoodooI2CPrecisionTouchpadHIDEventDriver 2>/dev/null | grep -E '\+-o' | head
ioreg -w0 -r -c VoodooI2CMultitouchInterface 2>/dev/null | grep -E '\+-o' | head
echo "== ioreg：AppleMultitouch"; ioreg -w0 -r -c AppleMultitouchDevice 2>/dev/null | grep -E '\+-o' | head
echo "== 中斷次數（powermetrics 3 秒）"; powermetrics -n 1 -i 3000 --samplers interrupts 2>/dev/null | grep -iE "I2C|PIXA|TPAD|AMDI0010" | head -20
echo "== 本次開機 VoodooI2C 日誌（kernel）"; log show --last boot --predicate 'process == "kernel" AND (eventMessage CONTAINS[c] "voodoo" OR eventMessage CONTAINS[c] "i2c")' --style compact 2>/dev/null | tail -80
echo "== dmesg"; dmesg 2>/dev/null | grep -iE "voodoo|i2c|pixa|tpad" | tail -60
} > "$O" 2>&1
chown kaoru:staff "$O" 2>/dev/null
echo "已存到 $O"
