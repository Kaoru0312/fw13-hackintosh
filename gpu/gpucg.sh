#!/bin/bash
# GFX 時鐘閘控（MGCG + CGCG/CGLS）開／關／狀態。phxboot.sh 開機時呼叫 `gpucg.sh on`。
#   - 寫入序列照 mechrevo-f7bsc `macos/thermal/gpucg.sh all`（MIT，原作 QiRanChenk/MECHREVO-WUJIE15XA-8745HS-Hackintosh tools/，
#     依 Linux gfx_v11_0_update_gfx_clock_gating()，GC 11.0.1）。
#   - FW13 實測（2026-11-24，gpu/gpucg-1124-045239.txt）：閒置封裝 9.95 → 7.91 W，GPU 正常。
#   - 安裝位置：/Users/Shared/gpu/gpucg.sh（由 gpu/gpucg-install.sh 複製）。停用開機套用：建立 /Users/Shared/gpu/gpucg-off。
# 用法：gpucg.sh on|off|status   （on/off 要 root）
set -u
P=/Users/Shared/gpu/phxctl/phxctl
SAFE=0xA980; OVR=0xEC48; CGCG=0xEC49; CGCG3D=0xECC5; POLL=0x21C2; INT0=0x306A; SDMA=0x12BC
# 2026-11-24 在 FW13 讀到的原值（GPU 接管、閘控未開），off 時寫回
ORIG_OVR=0x000607ff; ORIG_CGCG=0x0001003c; ORIG_CGCG3D=0x0001003c; ORIG_POLL=0x00400000; ORIG_INT0=0x00000000; ORIG_SDMA=0x00400000
rd() { "$P" regs "$1" | awk '{print $2}'; }
wr() { "$P" wreg "$1" "$2" >/dev/null; }
status() { for r in $OVR $CGCG $CGCG3D $POLL $INT0 $SDMA; do printf "%s=%s " "$r" "$(rd "$r")"; done; echo; }
safe_enter() { wr $SAFE 0x3; local i=0 v; while [ $i -lt 50 ]; do v=$(rd $SAFE); [ $(( v & 1 )) -eq 0 ] && return 0; i=$((i+1)); done; echo "RLC safe mode 沒有回應（$v），不寫入"; wr $SAFE 0x1; return 1; }
safe_exit() { wr $SAFE 0x1; }
on() {
  local v
  v=$(rd $OVR);    wr $OVR    "$(printf 0x%x $(( v & ~0x98 )))"
  v=$(rd $CGCG);   wr $CGCG   "$(printf 0x%x $(( (v & ~0x07FFFFFC) | (0x36 << 8) | (0xF << 2) | 0x3 )))"
  v=$(rd $CGCG3D); wr $CGCG3D "$(printf 0x%x $(( (v & ~0x07FFFFFC) | (0x36 << 8) | (0xF << 2) | 0x3 )))"
  wr $POLL 0x00900100
  v=$(rd $INT0);   wr $INT0   "$(printf 0x%x $(( v | 0x003C0000 )))"
  v=$(rd $SDMA);   wr $SDMA   "$(printf 0x%x $(( v | 0x2 )))"
  v=$(rd $OVR);    wr $OVR    "$(printf 0x%x $(( v & ~0x726 )))"
}
off() { wr $CGCG $ORIG_CGCG; wr $CGCG3D $ORIG_CGCG3D; wr $INT0 $ORIG_INT0; wr $SDMA $ORIG_SDMA; wr $POLL $ORIG_POLL; wr $OVR $ORIG_OVR; }
case "${1:-}" in
  status) status ;;
  on)  safe_enter || exit 1; on;  safe_exit; status ;;
  off) safe_enter || exit 1; off; safe_exit; status ;;
  *) echo "用法：$0 on|off|status"; exit 2 ;;
esac
