#!/bin/bash
# 在 phxboot.sh 加入「開機自動限制 SMU 時脈」：GFX 上限 800 MHz（實際下限）、FCLK 上限 800（SMU 實際給 1400 MHz）。
# 放在 phxboot 標記檔 (phxboot.pending) 移除之前：萬一這一步讓系統卡死，下次開機 phxboot 會自己關掉 GPU 接管（原本的保險機制）。
# 開關：建立 /Users/Shared/gpu/phxboot-noclk 就跳過（不用改回腳本）。需要 boot-arg phxdebug=1（目前有）。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/clk/install.sh
# 還原：sudo cp /Users/Shared/gpu/phxboot.sh.bak-clk /Users/Shared/gpu/phxboot.sh
set -euo pipefail
F=/Users/Shared/gpu/phxboot.sh; BK=$F.bak-clk
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
grep -q 'phxboot-noclk' "$F" && { echo "phxboot.sh 已經有時脈限制，不重複加入"; exit 0; }
[ "$(grep -c '^rm -f "\$MARK"; sync$' "$F")" = 1 ] || { echo "找不到唯一的插入點，停止（沒有改任何東西）"; exit 1; }
[ -e "$BK" ] || cp -p "$F" "$BK"
echo "已備份：$BK"
python3 - "$F" <<'EOF'
import sys
p=sys.argv[1]; s=open(p).read()
block='''# [port] fw13: cap the SMU clocks (nothing manages GFX/FCLK DPM on macOS, idle sat at GFX 2600 / FCLK 1600 MHz, ~33 W
# package; capped ~13 W, 2026-11-21). Kill switch: the file $G/phxboot-noclk. Before the marker goes, so a hang here
# turns phxboot off on the next boot like any other failure.
if [ ! -e $G/phxboot-noclk ]; then
    $G/phxctl/phxctl smu 0x1B 800 || true
    $G/phxctl/phxctl smu 0x1E 800 || true
    echo "[port] clocks: gfx $($G/phxctl/phxctl smu 0x17 0 | grep -o 'out 0x[0-9a-f]*') fclk $($G/phxctl/phxctl smu 0x18 0 | grep -o 'out 0x[0-9a-f]*')"
fi
'''
anchor='rm -f "$MARK"; sync\n'
assert s.count(anchor)==1
s=s.replace(anchor, block+anchor)
open(p,'w').write(s)
EOF
bash -n "$F" && echo "語法檢查 OK"
diff "$BK" "$F" || true
echo "完成。重開機後 /var/log/phxboot.log 會有一行 [port] clocks: …"
