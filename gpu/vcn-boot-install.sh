#!/bin/bash
# 讓 phxboot 每次開機在閘控／SDMA 之後把 VCN 帶起來（vcnctl check && vcnctl up），App 經 PhxBringup selector 130 解碼時就不用 root。
#   - 複製 vcn/vcnctl 和 vcn/fw/vcn_4_0_2.bin → /Users/Shared/gpu/vcn/。
#   - /Users/Shared/gpu/phxboot.sh：在 SDMA 那段之後、移除 pending 標記（rm -f "$MARK"）之前加一段；這裡讓開機卡住的話，
#     下次開機 phxboot 會跟其他失敗一樣自動建立 phxboot-off。輸出寫到 /var/log/vcn-up.log。
#   - 需要 PhxBringup build 135 以上（VCN 解碼介面）；2026-11-24 量過 VCN 開著閒置封裝中位數 7.11 W（沒開時 7.27 W，差異在雜訊內）。
#   - 備份：/Users/Shared/gpu/phxboot.sh.bak-vcn；repo 的 nullarc-pkg/gpu/phxboot.sh 同步更新。
#
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/gpu/vcn-boot-install.sh
#
# 出問題才用（現在不要執行）：
#   停用但保留安裝：sudo touch /Users/Shared/gpu/vcn-off   （下次開機生效）
#   完全還原：      sudo cp /Users/Shared/gpu/phxboot.sh.bak-vcn /Users/Shared/gpu/phxboot.sh
set -euo pipefail
G=/Users/Shared/gpu
F=$G/phxboot.sh
BAK=$F.bak-vcn
REPO=/Users/kaoru/fw13-hackintosh
ANCHOR='rm -f "$MARK"; sync'

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$F" ] || { echo "找不到 ${F}"; exit 1; }
[ -x "$REPO/vcn/vcnctl" ] || { echo "找不到編好的 $REPO/vcn/vcnctl"; exit 1; }
[ -f "$REPO/vcn/fw/vcn_4_0_2.bin" ] || { echo "找不到 $REPO/vcn/fw/vcn_4_0_2.bin"; exit 1; }
B=$(ioreg -r -c PhxBringup -d 1 | awk -F'= ' '/"phx-build"/{print $2}')
[ "${B:-0}" -ge 135 ] || { echo "PhxBringup build 是 ${B:-?}，要 135 以上"; exit 1; }
grep -q 'sdma.sh on' "$F" || { echo "${F} 裡沒有 SDMA 那段（先裝 sdma-install.sh），停止"; exit 1; }
grep -q 'vcnctl' "$F" && { echo "${F} 已經有 vcnctl，停止（不重複加）"; exit 1; }
[ "$(grep -cF "$ANCHOR" "$F")" = 1 ] || { echo "${F} 裡找不到唯一的 '${ANCHOR}'，停止"; exit 1; }

mkdir -p $G/vcn
install -m 755 -o root -g wheel "$REPO/vcn/vcnctl" $G/vcn/vcnctl
install -m 644 -o root -g wheel "$REPO/vcn/fw/vcn_4_0_2.bin" $G/vcn/vcn_4_0_2.bin
cp -p "$F" "$BAK"
python3 - "$F" "$ANCHOR" <<'PY'
import sys
p, anchor = sys.argv[1], sys.argv[2]
s = open(p).read()
block = '''# [port] fw13: bring VCN 4.0.2 up so apps can decode H.264 through PhxBringup selector 130 without root (vcn/HWDEC-PLAN.md).
# Idle package with VCN up 7.11 W vs 7.27 W (2026-11-24). Kill switch: $G/vcn-off. Before the marker goes, like the blocks above.
if [ ! -e $G/vcn-off ] && [ -x $G/vcn/vcnctl ]; then
    { $G/vcn/vcnctl check && $G/vcn/vcnctl up --fw $G/vcn/vcn_4_0_2.bin && $G/vcn/vcnctl ringtest; } > /var/log/vcn-up.log 2>&1
    echo "[port] vcn up: rc $? ($(grep -c '✅' /var/log/vcn-up.log) ok lines)"
fi
'''
s = s.replace(anchor, block + anchor, 1)
open(p, 'w').write(s)
PY
bash -n "$F" || { echo "語法檢查失敗，還原"; cp -p "$BAK" "$F"; exit 1; }
cp "$F" "$REPO/nullarc-pkg/gpu/phxboot.sh"; chown "$(stat -f %Su "$REPO")" "$REPO/nullarc-pkg/gpu/phxboot.sh"
echo "--- 差異"; diff "$BAK" "$F" || true
echo "已安裝。重開機後看：grep -E 'sdma|vcn up|^done' /var/log/phxboot.log | tail -3 ；詳細在 /var/log/vcn-up.log"
