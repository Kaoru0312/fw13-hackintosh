#!/bin/bash
# phxboot 開機時開放 Metal 給所有 App（760M 拓撲已修好：PhxBringup 8 CU、RADV num_cu 8 / RB 0x5）。
#   - 只改 /Users/Shared/gpu/phxboot.sh 第 76 行附近那一行（M2 路徑寫允許清單的地方），
#     換成 upstream 的寫法：all_apps "<註解>" '!WindowServer'（擋 mediaanalysisd / photoanalysisd / Spotlight）。
#   - 非 M2 路徑（apps_only）不動；這台一直走 M2（/Users/Shared/gpu/phxboot-m2 存在）。
#   - 備份：/Users/Shared/gpu/phxboot.sh.bak-allapps；repo 的 nullarc-pkg/gpu/phxboot.sh 同步更新。
#
# 用法：
#   sudo bash /Users/kaoru/fw13-hackintosh/gpu/all-apps.sh
#
# 出問題才用（現在不要執行）：
#   sudo cp /Users/Shared/gpu/phxboot.sh.bak-allapps /Users/Shared/gpu/phxboot.sh
#   （立即生效的話再加：sudo cp /Users/Shared/gpu/nvmtl-allow.txt.bak /Library/GPUBundles/nvmtl-allow.txt）
set -euo pipefail
F=/Users/Shared/gpu/phxboot.sh
BAK=$F.bak-allapps
REPO=/Users/kaoru/fw13-hackintosh/nullarc-pkg/gpu/phxboot.sh
OLD="    printf '# phxboot [port]: WindowServer composites on the GPU (armed only); apps stay on the CPU\\n!WindowServer\\n' > \$ALLOW"
NEW="    all_apps \"; WindowServer composites on the 760M (armed only) [port: 760M topology fixed 2026-11-21]\" '!WindowServer'"
OLD2='    echo "[port] Metal for WindowServer (armed) and the test tools only"'
NEW2='    echo "[port] Metal for every app (WindowServer armed; mediaanalysisd/photoanalysisd/Spotlight denied)"' 

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
[ -e "$BAK" ] && { echo "${BAK} 已存在，停止（可能已經跑過）"; exit 1; }
[ "$(grep -cxF -- "$OLD" "$F")" = 1 ] || { echo "phxboot.sh 裡找不到（或不只一處）要換的那一行，停止"; exit 1; }
grep -q '^all_apps()' "$F" || { echo "phxboot.sh 裡沒有 all_apps() 函式，停止"; exit 1; }
[ "$(grep -cxF -- "$OLD2" "$F")" = 1 ] || { echo "phxboot.sh 裡找不到（或不只一處）要換的 echo，停止"; exit 1; }

echo "== 1. 備份"
cp -p "$F" "$BAK"
echo "  → ${BAK}"

echo "== 2. 換掉那一行"
/usr/bin/python3 -I - "$F" "$OLD" "$NEW" "$OLD2" "$NEW2" <<'EOF'
import sys
p, old, new, old2, new2 = sys.argv[1:6]
s = open(p, encoding="utf-8").read()
assert s.count(old + "\n") == 1 and s.count(old2 + "\n") == 1
s = s.replace(old + "\n", new + "\n", 1).replace(old2 + "\n", new2 + "\n", 1)
open(p, "w", encoding="utf-8").write(s)
EOF
bash -n "$F" && echo "  語法檢查 OK"
diff "$BAK" "$F" || true

echo "== 3. 同步 repo 副本"
cp "$F" "$REPO"; chown kaoru:staff "$REPO"
echo "  → ${REPO}"

echo ""
echo "完成。下次開機 phxboot 會寫入 all_apps 清單（現在的臨時清單已經是同樣內容，不用重開）。"
