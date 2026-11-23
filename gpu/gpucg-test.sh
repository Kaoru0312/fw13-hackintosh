#!/bin/bash
# GFX 時鐘閘控實驗（MGCG + CGCG/CGLS）：量閒置封裝功耗，並持續確認 GPU 還活著。
#   - 2026-11-24 唯讀檢查：RLC_CGTT_MGCG_OVERRIDE(0xEC48)=0x000607ff（所有 override 都開著）、RLC_CGCG_CGLS_CTRL(0xEC49)
#     與 _3D(0xECC5)=0x0001003c（enable 位元 0–1 都是 0）→ nullarc 把 GFX 時鐘閘控整個留在重設值，閒置時時鐘不會停。
#   - 寫入序列照 mechrevo-f7bsc `macos/thermal/gpucg.sh`（MIT，原作 QiRanChenk/MECHREVO-WUJIE15XA-8745HS-Hackintosh tools/，
#     依 Linux gfx_v11_0_update_gfx_clock_gating()；同為 GC 11.0.1）。上游 nullarc PR #14 build 37（9f37791）做同一件事，
#     量到閒置 8.0 → 6.5 W（ACEMAGIC RX16）、8.8 → 6.75 W（另一台 780M）。FW13 沒量過。
#   - 只是暫存器的執行期狀態，重開機就恢復（GPU 重新初始化會清掉）。
#   - 安全機制：每 10 秒跑一次 mtlprobe，失敗或 20 秒沒回應 → 寫回實驗前讀到的原值。
#   - 結果寫到 /Users/kaoru/fw13-hackintosh/gpu/gpucg-<時間>.txt
#
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/gpu/gpucg-test.sh            （跑完維持閘控開著，除非出事）
#       sudo bash /Users/kaoru/fw13-hackintosh/gpu/gpucg-test.sh --restore  （寫回 2026-11-24 讀到的原值）
#       sudo bash /Users/kaoru/fw13-hackintosh/gpu/gpucg-test.sh --status   （只讀）
# 跑的時候請不要碰觸控板和鍵盤，Claude app 縮到 Dock、AMD Power Gadget 關掉。
set -u
PHXCTL=/Users/Shared/gpu/phxctl/phxctl
PROBE=/Users/kaoru/fw13-hackintosh/nullarc-test/mtlprobe
SMC=/tmp/smcdump
OUT=/Users/kaoru/fw13-hackintosh/gpu/gpucg-$(date +%m%d-%H%M%S).txt
SAFE=0xA980; OVR=0xEC48; CGCG=0xEC49; CGCG3D=0xECC5; POLL=0x21C2; INT0=0x306A; SDMA=0x12BC
REGS="$OVR $CGCG $CGCG3D $POLL $INT0 $SDMA"
# 2026-11-24 04:5x 在 FW13 讀到的值（GPU 接管、閒置）
ORIG_OVR=0x000607ff; ORIG_CGCG=0x0001003c; ORIG_CGCG3D=0x0001003c; ORIG_POLL=0x00400000; ORIG_INT0=0x00000000; ORIG_SDMA=0x00400000

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -x "$PHXCTL" ] || { echo "找不到 ${PHXCTL}"; exit 1; }

rd() { "$PHXCTL" regs "$1" | awk '{print $2}'; }
wr() { "$PHXCTL" wreg "$1" "$2" >/dev/null; }
status() { for r in $REGS; do printf "%s=%s " "$r" "$(rd "$r")"; done; echo; }
safe_enter() { wr $SAFE 0x3; local i=0 v; while [ $i -lt 50 ]; do v=$(rd $SAFE); [ $(( v & 1 )) -eq 0 ] && return 0; i=$((i+1)); done; echo "  RLC safe mode 沒有回應（$v），不寫入"; wr $SAFE 0x1; return 1; }
safe_exit() { wr $SAFE 0x1; }
apply() {   # = gpucg.sh all（先 cgcg 再 mgcg）
  local v
  v=$(rd $OVR);    wr $OVR    "$(printf 0x%x $(( v & ~0x98 )))"
  v=$(rd $CGCG);   wr $CGCG   "$(printf 0x%x $(( (v & ~0x07FFFFFC) | (0x36 << 8) | (0xF << 2) | 0x3 )))"
  v=$(rd $CGCG3D); wr $CGCG3D "$(printf 0x%x $(( (v & ~0x07FFFFFC) | (0x36 << 8) | (0xF << 2) | 0x3 )))"
  wr $POLL 0x00900100
  v=$(rd $INT0);   wr $INT0   "$(printf 0x%x $(( v | 0x003C0000 )))"
  v=$(rd $SDMA);   wr $SDMA   "$(printf 0x%x $(( v | 0x2 )))"
  v=$(rd $OVR);    wr $OVR    "$(printf 0x%x $(( v & ~0x726 )))"
}
restore() {   # 先關 enable、再寫回 override 與原值
  safe_enter || return 1
  wr $CGCG $ORIG_CGCG; wr $CGCG3D $ORIG_CGCG3D; wr $INT0 $ORIG_INT0; wr $SDMA $ORIG_SDMA; wr $POLL $ORIG_POLL; wr $OVR $ORIG_OVR
  safe_exit
}

case "${1:-}" in
  --status)  status; exit 0 ;;
  --restore) restore && echo "已寫回原值：$(status)"; exit 0 ;;
  "") ;;
  *) echo "用法：$0 [--status|--restore]"; exit 2 ;;
esac

nvram boot-args | grep -q phxdebug=1 || { echo "boot-args 沒有 phxdebug=1，phxctl 不能用"; exit 1; }
[ -x "$PROBE" ] || { echo "找不到 ${PROBE}"; exit 1; }
[ -e /Users/Shared/gpu/phxboot-off ] && { echo "GPU 接管是關的（phxboot-off 存在），停止"; exit 1; }
pgrep -x "AMD Power Gadget" >/dev/null && { echo "AMD Power Gadget 開著，請先關掉"; exit 1; }
[ -x "$SMC" ] || cc -O2 -framework IOKit -framework CoreFoundation /Users/kaoru/fw13-hackintosh/tools/smcdump.c -o "$SMC"

exec > >(tee "$OUT") 2>&1
pw() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{print $2}'; }
c0() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"C0PermilleAvg"/{print $2}'; }
gfx() { "$PHXCTL" smu 0x17 0 2>&1 | grep -o 'out 0x[0-9a-f]*' | head -1; }
probe() {   # 回傳 0 = GPU 正常
    "$PROBE" > /tmp/gpucg-probe.txt 2>&1 & local p=$!
    for _ in $(seq 1 20); do kill -0 $p 2>/dev/null || break; sleep 1; done
    if kill -0 $p 2>/dev/null; then kill -9 $p 2>/dev/null; echo "  mtlprobe 20 秒沒回應"; return 1; fi
    grep -q "4096/4096 correct" /tmp/gpucg-probe.txt || { echo "  mtlprobe 結果不對：$(tail -1 /tmp/gpucg-probe.txt)"; return 1; }
    return 0
}
revert() { echo "!! $(date +%T) 寫回原值"; restore; sleep 2; probe && echo "  GPU 恢復正常" || echo "  GPU 仍異常：請重開機（閘控狀態不會保留）"; }

echo "== $(date '+%F %T') GFX 時鐘閘控實驗  uptime: $(uptime | sed 's/.*up //; s/,.*//')"
echo "== 0. 事前檢查"
[ -n "$(pw)" ] || echo "  注意：讀不到 AMDPMProbe 的 PackagePowerMilliWatt（[41] 沒載入？），功耗欄會是空的"
echo "  暫存器 $(status)"
[ "$(rd $OVR)" = "$ORIG_OVR" ] || echo "  注意：0xEC48 跟 11-24 讀到的 ${ORIG_OVR} 不同，--restore 會寫回 11-24 的值"
probe && echo "  mtlprobe OK" || { echo "  實驗前 GPU 就不正常，停止"; exit 1; }
echo "  GFXCLK $(gfx)"
echo "== 1. 基準 60 秒（閘控未開）"
for i in $(seq 1 12); do echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)"; sleep 5; done

echo "== 2. 開時鐘閘控（RLC safe mode 內寫入）"
safe_enter || exit 1
apply
safe_exit
echo "  暫存器 $(status)"
sleep 3
probe || { revert; exit 1; }
echo "== 3. 開啟後 90 秒（每 10 秒確認 GPU）"
ok=1
for i in $(seq 1 9); do
    echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)  GFXCLK $(gfx)"
    sleep 5
    echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)"
    if ! probe; then ok=0; revert; break; fi
done
[ $ok = 1 ] && echo "== 結果：90 秒內 GPU 一直正常。閘控維持開著；要關掉：sudo bash $0 --restore（或重開機）"
echo "== 4. WindowServer：$(pgrep -x WindowServer >/dev/null && echo 在跑 || echo 不見了)"
echo "結果存在 ${OUT}"
