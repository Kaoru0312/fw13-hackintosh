#!/bin/bash
# SDMA0 解除 halt／設回 halt／狀態，讓 RLC 的粗粒度時鐘閘控（CGCG）能完成握手。phxboot.sh 開機時在 gpucg.sh on 之後呼叫 `sdma.sh on`。
#   - 依據：nullarc PR #24 37a7b16（mesboot sdma_unhalt）。上游在開機時、MES 初始化前做；FW13 是佇列建好、閘控開之後才做（實驗驗證過的順序）。
#   - FW13 實測（2026-11-24，gpu/sdma-1124-052351.txt、power/idle-1124-052717.txt）：RLC_GPM_STAT 0x00140016 → 0x000c001a（Linux 的值），
#     閒置封裝中位數 8.03 → 7.27 W（不同次開機）。用了一段時間沒有自己重開（上游 RX16 有重開紀錄）。
#   - 安裝位置：/Users/Shared/gpu/sdma.sh（由 gpu/sdma-install.sh 複製）。停用開機套用：建立 /Users/Shared/gpu/sdma-off。
# 用法：sdma.sh on|off|status   （要 root）
set -u
P=/Users/Shared/gpu/phxctl/phxctl
F32=0xF89A; CNTL=0x127C; STAT=0x1285; GPM=0xEE6B
ORIG_CNTL=0x00002440
rd() { "$P" regs "$1" | awk '{print $2}'; }
wr() { "$P" wreg "$1" "$2" >/dev/null; }
status() { local s; s=$(rd $STAT); echo "F32_CNTL=$(rd $F32) CNTL=$(rd $CNTL) CGCG_FENCE=$(( (s >> 11) & 1 )) RLC_GPM_STAT=$(rd $GPM)"; }
case "${1:-}" in
  status) status ;;
  on)  v=$(rd $F32); wr $F32 "$(printf 0x%x $(( v & ~1 )))"; v=$(rd $CNTL); wr $CNTL "$(printf 0x%x $(( v | (1 << 28) )))"; sleep 1; status ;;
  off) v=$(rd $F32); wr $F32 "$(printf 0x%x $(( v | 1 )))"; wr $CNTL $ORIG_CNTL; status ;;
  *) echo "用法：$0 on|off|status"; exit 2 ;;
esac
