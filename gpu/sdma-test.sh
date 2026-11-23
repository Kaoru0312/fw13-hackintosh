#!/bin/bash
# GFXOFF 階段 1a：執行期讓 SDMA0 離開 halt，讓 RLC 的粗粒度時鐘閘控（CGCG）能完成握手。量閒置功耗並持續確認 GPU 還活著。
#   - 依據：nullarc PR #24 37a7b16（mesboot sdma_unhalt）。上游在開機時、MES 初始化前做；這裡是佇列都建好之後才做，
#     上游沒試過這個時機，安不安全不知道。
#   - 2026-11-24 階段 0 讀值跟上游修正前完全一樣：SDMA0_F32_CNTL 0x08084001（HALT=1）、SDMA0_CNTL 0x00002440（缺 bit 28）、
#     SDMA0_STATUS_REG bit 11（CGCG_FENCE）= 0、RLC_GPM_STAT 0x00140016。上游修正後 RLC_GPM_STAT = Linux 的 0x000c001a。
#   - 上游風險（0a3bd8a）：ACEMAGIC RX16 在 SDMA 運作時 45 分鐘內自己重開 3 次，原因不明；WUJIE15XA 13 小時沒事。
#   - 只是執行期狀態，重開機就恢復 halt。前提：GFX 時鐘閘控已開（gpucg.sh on）。
#   - 安全機制：每 10 秒跑一次 mtlprobe，失敗或 20 秒沒回應 → 把 HALT 設回 1、SDMA0_CNTL 寫回原值。
#   - 結果寫到 /Users/kaoru/fw13-hackintosh/gpu/sdma-<時間>.txt
#
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/gpu/sdma-test.sh            （跑完維持 SDMA 運作，除非出事）
#       sudo bash /Users/kaoru/fw13-hackintosh/gpu/sdma-test.sh --halt     （設回 halt）
#       sudo bash /Users/kaoru/fw13-hackintosh/gpu/sdma-test.sh --status   （只讀）
# 跑的時候請不要碰觸控板和鍵盤，Claude app 縮到 Dock、AMD Power Gadget 關掉。
set -u
PHXCTL=/Users/Shared/gpu/phxctl/phxctl
PROBE=/Users/kaoru/fw13-hackintosh/nullarc-test/mtlprobe
SMC=/tmp/smcdump
OUT=/Users/kaoru/fw13-hackintosh/gpu/sdma-$(date +%m%d-%H%M%S).txt
F32=0xF89A; CNTL=0x127C; STAT=0x1285; CGCTL=0x12BC; GPM=0xEE6B; PG=0xEC43; OVR=0xEC48
ORIG_CNTL=0x00002440

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -x "$PHXCTL" ] || { echo "找不到 ${PHXCTL}"; exit 1; }
rd() { "$PHXCTL" regs "$1" | awk '{print $2}'; }
wr() { "$PHXCTL" wreg "$1" "$2" >/dev/null; }
status() {
  local s; s=$(rd $STAT)
  echo "F32_CNTL=$(rd $F32) CNTL=$(rd $CNTL) STATUS=$s(CGCG_FENCE $(( (s >> 11) & 1 ))) CGCG_CTRL=$(rd $CGCTL) RLC_GPM_STAT=$(rd $GPM) RLC_PG_CNTL=$(rd $PG) MGCG_OVR=$(rd $OVR)"
}
unhalt() { local v; v=$(rd $F32); wr $F32 "$(printf 0x%x $(( v & ~1 )))"; v=$(rd $CNTL); wr $CNTL "$(printf 0x%x $(( v | (1 << 28) )))"; }
halt()   { local v; v=$(rd $F32); wr $F32 "$(printf 0x%x $(( v | 1 )))"; wr $CNTL $ORIG_CNTL; }

case "${1:-}" in
  --status) status; exit 0 ;;
  --halt)   halt; echo "已設回 halt：$(status)"; exit 0 ;;
  "") ;;
  *) echo "用法：$0 [--status|--halt]"; exit 2 ;;
esac

nvram boot-args | grep -q phxdebug=1 || { echo "boot-args 沒有 phxdebug=1，phxctl 不能用"; exit 1; }
[ -x "$PROBE" ] || { echo "找不到 ${PROBE}"; exit 1; }
[ -e /Users/Shared/gpu/phxboot-off ] && { echo "GPU 接管是關的（phxboot-off 存在），停止"; exit 1; }
pgrep -x "AMD Power Gadget" >/dev/null && { echo "AMD Power Gadget 開著，請先關掉"; exit 1; }
[ "$(rd $OVR)" = "0x00060041" ] || { echo "GFX 時鐘閘控沒開（0xEC48 不是 0x00060041），先跑 gpucg.sh on，停止"; exit 1; }
[ $(( $(rd $F32) & 1 )) -eq 1 ] || { echo "SDMA 已經不是 halt，停止（要重測先 --halt）"; exit 1; }
[ -x "$SMC" ] || cc -O2 -framework IOKit -framework CoreFoundation /Users/kaoru/fw13-hackintosh/tools/smcdump.c -o "$SMC"

exec > >(tee "$OUT") 2>&1
pw() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"PackagePowerMilliWatt"/{print $2}'; }
c0() { ioreg -r -c AMDPMProbe -l | awk -F'= ' '/"C0PermilleAvg"/{print $2}'; }
probe() {   # 回傳 0 = GPU 正常
    "$PROBE" > /tmp/sdma-probe.txt 2>&1 & local p=$!
    for _ in $(seq 1 20); do kill -0 $p 2>/dev/null || break; sleep 1; done
    if kill -0 $p 2>/dev/null; then kill -9 $p 2>/dev/null; echo "  mtlprobe 20 秒沒回應"; return 1; fi
    grep -q "4096/4096 correct" /tmp/sdma-probe.txt || { echo "  mtlprobe 結果不對：$(tail -1 /tmp/sdma-probe.txt)"; return 1; }
    return 0
}
revert() { echo "!! $(date +%T) 設回 halt"; halt; sleep 2; probe && echo "  GPU 恢復正常" || echo "  GPU 仍異常：請重開機（SDMA 會回到 halt）"; }

echo "== $(date '+%F %T') SDMA 解除 halt 實驗  uptime: $(uptime | sed 's/.*up //; s/,.*//')"
echo "== 0. 事前檢查"
echo "  $(status)"
probe && echo "  mtlprobe OK" || { echo "  實驗前 GPU 就不正常，停止"; exit 1; }
echo "== 1. 基準 60 秒（SDMA halt）"
for i in $(seq 1 12); do echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)"; sleep 5; done

echo "== 2. SDMA 解除 halt"
unhalt
sleep 1
echo "  $(status)"
probe || { revert; exit 1; }
echo "== 3. 解除後 90 秒（每 10 秒確認 GPU；RLC_GPM_STAT 每 10 秒記一次）"
ok=1
for i in $(seq 1 9); do
    echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)  RLC_GPM_STAT $(rd $GPM)"
    sleep 5
    echo "  $(date +%T) $(pw) mW C0=$(c0)‰ $($SMC TC0P)"
    if ! probe; then ok=0; revert; break; fi
done
echo "  結束時 $(status)"
[ $ok = 1 ] && echo "== 結果：90 秒內 GPU 一直正常。SDMA 維持運作；要設回：sudo bash $0 --halt（或重開機）"
echo "== 4. WindowServer：$(pgrep -x WindowServer >/dev/null && echo 在跑 || echo 不見了)"
echo "結果存在 ${OUT}"
