#!/bin/bash
# 讓 phxboot 每次開機自動開 GFX 時鐘閘控。
#   - 複製 gpu/gpucg.sh → /Users/Shared/gpu/gpucg.sh。
#   - /Users/Shared/gpu/phxboot.sh：在 SMU 時脈限制那段之後、移除 pending 標記（rm -f "$MARK"）之前，加一段呼叫 gpucg.sh on。
#     放在標記移除之前：這裡如果讓開機卡住，下次開機 phxboot 會跟其他失敗一樣自動建立 phxboot-off。
#   - 備份：/Users/Shared/gpu/phxboot.sh.bak-gpucg；repo 的 nullarc-pkg/gpu/phxboot.sh 同步更新。
#   - 開機 log：/var/log/phxboot.log 會多一行「[port] gpucg: …」。
#
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/gpu/gpucg-install.sh
#
# 出問題才用（現在不要執行）：
#   停用但保留安裝：sudo touch /Users/Shared/gpu/gpucg-off   （下次開機生效）
#   完全還原：      sudo cp /Users/Shared/gpu/phxboot.sh.bak-gpucg /Users/Shared/gpu/phxboot.sh
#   CachyOS 下救援：不需要（這個改動在 macOS 系統磁碟上，不在 ESP）；macOS 進不了桌面時 phxboot 會自動退回 CPU 繪製。
set -euo pipefail
G=/Users/Shared/gpu
F=$G/phxboot.sh
BAK=$F.bak-gpucg
REPO=/Users/kaoru/fw13-hackintosh
ANCHOR='rm -f "$MARK"; sync'

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -f "$F" ] || { echo "找不到 ${F}"; exit 1; }
grep -q 'gpucg' "$F" && { echo "${F} 已經有 gpucg，停止（不重複加）"; exit 1; }
[ "$(grep -cF "$ANCHOR" "$F")" = 1 ] || { echo "${F} 裡找不到唯一的 '${ANCHOR}'，停止"; exit 1; }

install -m 755 -o root -g wheel "$REPO/gpu/gpucg.sh" $G/gpucg.sh
cp -p "$F" "$BAK"
python3 - "$F" "$ANCHOR" <<'PY'
import sys
p, anchor = sys.argv[1], sys.argv[2]
s = open(p).read()
block = '''# [port] fw13: GFX clock gating (MGCG + CGCG/CGLS) that the bring-up leaves at reset defaults; idle package 9.95 -> 7.91 W
# (2026-11-24). Kill switch: the file $G/gpucg-off. Before the marker goes, like the clock caps above.
if [ ! -e $G/gpucg-off ] && [ -x $G/gpucg.sh ]; then
    echo "[port] gpucg: $($G/gpucg.sh on 2>&1)"
fi
'''
s = s.replace(anchor, block + anchor, 1)
open(p, 'w').write(s)
PY
bash -n "$F" || { echo "語法檢查失敗，還原"; cp -p "$BAK" "$F"; exit 1; }
cp "$F" "$REPO/nullarc-pkg/gpu/phxboot.sh"; chown "$(stat -f %Su "$REPO")" "$REPO/nullarc-pkg/gpu/phxboot.sh"
echo "--- 差異"; diff "$BAK" "$F" || true
echo "已安裝。重開機後看：grep gpucg /var/log/phxboot.log ；以及 sudo $G/gpucg.sh status"
