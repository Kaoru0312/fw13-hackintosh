#!/bin/bash
# 讓 phxboot 每次開機在開 GFX 時鐘閘控之後，讓 SDMA0 離開 halt。
#   - 複製 gpu/sdma.sh → /Users/Shared/gpu/sdma.sh。
#   - /Users/Shared/gpu/phxboot.sh：在 gpucg 那段之後、移除 pending 標記（rm -f "$MARK"）之前加一段。這裡讓開機卡住的話，
#     下次開機 phxboot 會跟其他失敗一樣自動建立 phxboot-off。只在閘控真的開了（0xEC48 = 0x00060041）才做。
#   - 備份：/Users/Shared/gpu/phxboot.sh.bak-sdma；repo 的 nullarc-pkg/gpu/phxboot.sh 同步更新。
#
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/gpu/sdma-install.sh
#
# 出問題才用（現在不要執行）：
#   停用但保留安裝：sudo touch /Users/Shared/gpu/sdma-off   （下次開機生效）
#   完全還原：      sudo cp /Users/Shared/gpu/phxboot.sh.bak-sdma /Users/Shared/gpu/phxboot.sh
set -euo pipefail
G=/Users/Shared/gpu
F=$G/phxboot.sh
BAK=$F.bak-sdma
REPO=/Users/kaoru/fw13-hackintosh
ANCHOR='rm -f "$MARK"; sync'

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$F" ] || { echo "找不到 ${F}"; exit 1; }
grep -q 'gpucg.sh on' "$F" || { echo "${F} 裡沒有 gpucg（要先裝 gpucg-install.sh），停止"; exit 1; }
grep -q 'sdma' "$F" && { echo "${F} 已經有 sdma，停止（不重複加）"; exit 1; }
[ "$(grep -cF "$ANCHOR" "$F")" = 1 ] || { echo "${F} 裡找不到唯一的 '${ANCHOR}'，停止"; exit 1; }

install -m 755 -o root -g wheel "$REPO/gpu/sdma.sh" $G/sdma.sh
cp -p "$F" "$BAK"
python3 - "$F" "$ANCHOR" <<'PY'
import sys
p, anchor = sys.argv[1], sys.argv[2]
s = open(p).read()
block = '''# [port] fw13: take SDMA0 out of halt so the RLC can finish coarse grain clock gating (nullarc PR #24); RLC_GPM_STAT
# 0x00140016 -> 0x000c001a, idle package 8.03 -> 7.27 W (2026-11-24). Only with clock gating on. Kill switch: $G/sdma-off.
if [ ! -e $G/sdma-off ] && [ -x $G/sdma.sh ] && [ "$($G/phxctl/phxctl regs 0xEC48 | awk '{print $2}')" = 0x00060041 ]; then
    echo "[port] sdma: $($G/sdma.sh on 2>&1)"
fi
'''
s = s.replace(anchor, block + anchor, 1)
open(p, 'w').write(s)
PY
bash -n "$F" || { echo "語法檢查失敗，還原"; cp -p "$BAK" "$F"; exit 1; }
cp "$F" "$REPO/nullarc-pkg/gpu/phxboot.sh"; chown "$(stat -f %Su "$REPO")" "$REPO/nullarc-pkg/gpu/phxboot.sh"
echo "--- 差異"; diff "$BAK" "$F" || true
echo "已安裝。重開機後看：grep -E 'gpucg|sdma|^done' /var/log/phxboot.log | tail -3"
