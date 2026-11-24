#!/bin/bash
# 第 4 步測試：VCN 由 root 帶起來（vcnctl up），解碼改走 kext 的 PHXN_SEL_FW13_VCN_DEC，由一般使用者執行 kdec。
#   - 需要 FW13 版 PhxBringup（build 134，gpu/phxbringup-install.sh）。
#   - 跟 vcn-test.sh 一樣先排 4 分鐘自動重開，跑完取消。
# 用法：sudo bash /Users/kaoru/fw13-hackintosh/vcn/kdec-test.sh [--loops N]
set -u
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
HERE=$(cd "$(dirname "$0")" && pwd)
U=${SUDO_USER:-kaoru}
[ -x "$HERE/vcnctl" ] && [ -x "$HERE/kdec" ] || { echo "先編譯 vcnctl 和 kdec（指令在 HWDEC-PLAN.md 第 4 步）"; exit 1; }
B=$(ioreg -r -c PhxBringup -d 1 | awk -F'= ' '/"phx-build"/{print $2}')
[ "${B:-0}" -ge 134 ] || { echo "PhxBringup build 是 ${B:-?}，要 134 以上（先裝 gpu/phxbringup-install.sh 並重開機）"; exit 1; }
pgrep -x "AMD Power Gadget" >/dev/null && { echo "AMD Power Gadget 開著，請先關掉"; exit 1; }
LOG=$HERE/log-kdec-$(date +%m%d-%H%M%S).txt
exec > >(tee "$LOG") 2>&1
echo "== $(date '+%F %T')  uptime $(uptime | sed 's/.*up //; s/,.*//')  PhxBringup build ${B}"
"$HERE/vcnctl" check >/dev/null || { echo "vcnctl check 沒過，停止"; exit 1; }
WD=$(bash -c 'nohup shutdown -r +4 </dev/null >/dev/null 2>&1 & echo $!')
"$HERE/vcnctl" up >/dev/null; UP=$?
RES=1
if [ $UP = 0 ]; then
  RES=0
  for t in t1_ippp t2_ibbp t3_pyramid t4_720p; do
    sudo -u "$U" "$HERE/kdec" "$HERE/h264/testdata/$t.h264" "$HERE/h264/testdata/$t.framemd5" "$@" || RES=1
  done
else
  echo "vcnctl up 失敗（${UP}）"
fi
"$HERE/vcnctl" down >/dev/null
kill "$WD" 2>/dev/null; killall shutdown 2>/dev/null; echo "watchdog 已取消"
echo "== 結果：up=${UP} kdec=${RES}（0 = 成功）  WindowServer：$(pgrep -x WindowServer >/dev/null && echo 在跑 || echo 不見了)"
chown "$U":staff "$LOG" 2>/dev/null
