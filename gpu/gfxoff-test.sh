#!/bin/bash
# GFXOFF 實驗：允許 GPU 圖形核心在閒置時斷電（SMU AllowGfxOff 0x19），量功耗，並持續確認 GPU 還活著。
#   - nullarc 的 kext 和 phxboot 都沒有動過 GFXOFF；nullarc 文件記錄過「GFXOFF 允許時 CP 的 PFP 卡住，DisallowGfxOff(0x1A) 可解除」。
#   - 只是 SMU 的執行期狀態，重開機就恢復。
#   - 安全機制：每 10 秒跑一次 mtlprobe（Metal compute 4096/4096），失敗或 20 秒沒回應 → 立刻送 0x1A 關掉 GFXOFF。
#   - 結果寫到 /Users/kaoru/fw13-hackintosh/gpu/gfxoff-<時間>.txt
#
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/gpu/gfxoff-test.sh          （跑完維持 GFXOFF 開著，除非出事）
#       sudo bash /Users/kaoru/fw13-hackintosh/gpu/gfxoff-test.sh --off    （只送 0x1A 關掉）
# 跑的時候請不要碰觸控板和鍵盤，Claude app 縮到 Dock、AMD Power Gadget 關掉。
set -u
PHXCTL=/Users/Shared/gpu/phxctl/phxctl
PROBE=/Users/kaoru/fw13-hackintosh/nullarc-test/mtlprobe
SMC=/tmp/smcdump
OUT=/Users/kaoru/fw13-hackintosh/gpu/gfxoff-$(date +%m%d-%H%M%S).txt

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -x "$PHXCTL" ] || { echo "找不到 ${PHXCTL}"; exit 1; }
nvram boot-args | grep -q phxdebug=1 || { echo "boot-args 沒有 phxdebug=1，phxctl smu 不能用"; exit 1; }

if [ "${1:-}" = "--off" ]; then
    "$PHXCTL" smu 0x1a 0
    echo "已送 DisallowGfxOff (0x1A)。"
    exit 0
fi

[ -x "$PROBE" ] || { echo "找不到 ${PROBE}"; exit 1; }
[ -e /Users/Shared/gpu/phxboot-off ] && { echo "GPU 接管是關的（phxboot-off 存在），停止"; exit 1; }
pgrep -x "AMD Power Gadget" >/dev/null && { echo "AMD Power Gadget 開著，請先關掉"; exit 1; }
[ -x "$SMC" ] || cc -O2 -framework IOKit -framework CoreFoundation /Users/kaoru/fw13-hackintosh/tools/smcdump.c -o "$SMC"

exec > >(tee "$OUT") 2>&1
pw() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{print $2}'; }
c0() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"C0PermilleAvg"/{print $2}'; }
gfx() { "$PHXCTL" smu 0x17 0 2>&1 | grep -o 'out 0x[0-9a-f]*' | head -1; }
probe() {   # 回傳 0 = GPU 正常
    "$PROBE" > /tmp/gfxoff-probe.txt 2>&1 & local p=$!
    for _ in $(seq 1 20); do kill -0 $p 2>/dev/null || break; sleep 1; done
    if kill -0 $p 2>/dev/null; then kill -9 $p 2>/dev/null; echo "  mtlprobe 20 秒沒回應"; return 1; fi
    grep -q "4096/4096 correct" /tmp/gfxoff-probe.txt || { echo "  mtlprobe 結果不對：$(tail -1 /tmp/gfxoff-probe.txt)"; return 1; }
    return 0
}
revert() { echo "!! $(date +%T) 送 DisallowGfxOff (0x1A)"; "$PHXCTL" smu 0x1a 0; sleep 2; probe && echo "  GPU 恢復正常" || echo "  GPU 仍異常：請重開機（GFXOFF 狀態不會保留）"; }

echo "== $(date '+%F %T') GFXOFF 實驗  uptime: $(uptime | sed 's/.*up //; s/,.*//')"
echo "== 0. 事前檢查"
probe && echo "  mtlprobe OK" || { echo "  實驗前 GPU 就不正常，停止"; exit 1; }
echo "  GFXCLK $(gfx)"
echo "== 1. 基準 60 秒（GFXOFF 未送）"
for i in $(seq 1 12); do echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)"; sleep 5; done

echo "== 2. 送 AllowGfxOff (0x19)"
"$PHXCTL" smu 0x19 0
sleep 3
echo "  GFXCLK $(gfx)"
echo "== 3. GFXOFF 允許後 90 秒（每 10 秒確認 GPU）"
ok=1
for i in $(seq 1 9); do
    echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)  GFXCLK $(gfx)"
    sleep 5
    echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)"
    if ! probe; then ok=0; revert; break; fi
done
[ $ok = 1 ] && echo "== 結果：90 秒內 GPU 一直正常（mtlprobe 都 4096/4096）。GFXOFF 維持允許；要關掉：sudo bash $0 --off"
echo "== 4. WindowServer：$(pgrep -x WindowServer >/dev/null && echo 在跑 || echo 不見了)  frames $(sysctl -n debug.nvaccel_iop_ok 2>/dev/null)"
echo "結果存在 ${OUT}"
