#!/bin/bash
# 硬解階段 1/2a/2b 測試：vcnctl check → up → ringtest → ibtest → [decodetest] → [vmtest] → down，全部輸出存到 vcn/log-<時間>.txt。
#   - 先排一個 4 分鐘後的自動重開（跟 bringup5.sh 一樣），GPU 卡住時至少會自己重開；跑完正常就取消。
#   - 不在開機流程裡、不改 OpenCore、不改任何檔案；重開機後 VCN 回到斷電狀態。
#   - 跑之前：關掉 AMD Power Gadget（它也會碰 SMU）、存好手邊的工作。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/vcn/vcn-test.sh [--no-drmkey] [--trap] [--vm] [--dec]
#   --vm：另外跑階段 2b 的 MMHUB vmtest，結束會還原 MMHUB
#   --dec：另外跑 decodetest（解一張固定的 864×480 H.264 畫面，用 VRAM +0xD000000 起約 16 MiB，先確認那段 3 秒內沒被改才寫）
set -u
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
V=$HERE/vcnctl
[ -x "$V" ] || { echo "找不到 ${V}（先編譯：clang -O2 -Wall -framework IOKit -framework CoreFoundation ${HERE}/vcnctl.c -o ${V}）"; exit 1; }
[ -f "$HERE/fw/vcn_4_0_2.bin" ] || { echo "找不到 $HERE/fw/vcn_4_0_2.bin"; exit 1; }
pgrep -x "AMD Power Gadget" >/dev/null && { echo "AMD Power Gadget 開著，請先關掉"; exit 1; }
[ -e /Users/Shared/gpu/phxboot-off ] && { echo "GPU 接管是關的（phxboot-off），PSP ring 可能沒建立，停止"; exit 1; }
LOG=$HERE/log-$(date +%m%d-%H%M%S).txt
exec > >(tee "$LOG") 2>&1
echo "== $(date '+%F %T')  uptime $(uptime | sed 's/.*up //; s/,.*//')"
"$V" check || { echo "check 沒過，停止（沒有改任何東西）"; exit 1; }
echo "== watchdog：4 分鐘後自動重開，跑完會取消"
WD=$(bash -c 'nohup shutdown -r +4 </dev/null >/dev/null 2>&1 & echo $!')
"$V" up "$@"; UP=$?
RT=1
IB=1
if [ $UP = 0 ]; then "$V" ringtest; RT=$?; fi
if [ $RT = 0 ]; then "$V" ibtest "$@"; IB=$?; fi
DEC=-
case " $* " in *" --dec "*) DEC=1; if [ $IB = 0 ]; then "$V" decodetest --out "$HERE/dec-$(date +%m%d-%H%M%S).nv12"; DEC=$?; fi ;; esac
VM=-
case " $* " in *" --vm "*) VM=1; if [ $IB = 0 ]; then "$V" vmtest "$@"; VM=$?; fi ;; esac
"$V" down
kill "$WD" 2>/dev/null; killall shutdown 2>/dev/null; echo "watchdog 已取消"
echo "== 結果：up=${UP} ringtest=${RT} ibtest=${IB} decodetest=${DEC} vmtest=${VM}（0 = 成功）  WindowServer：$(pgrep -x WindowServer >/dev/null && echo 在跑 || echo 不見了)"
echo "紀錄存在 ${LOG}"
chown kaoru:staff "$LOG" "$HERE"/dec-*.nv12 2>/dev/null
