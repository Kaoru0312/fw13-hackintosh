#!/bin/bash
# 休眠第 5 步（第一次測試）的開關。只做「能不能從休眠映像還原」需要的設定，畫面能不能回來這次不管
# （PhxAccel 還沒有 PR #20 的 phxfb_wake／nvaccelfb=9，喚醒後畫面大概不會回來）。
#   on ：boot-args 拿掉 -v、debug=0x100（PR #20：帶著它們進入睡眠會卡住）；停用 Wi-Fi kext（AirportMtkWlan，見下方註解）；
#        pmset -a hibernatemode 25 standby 0 autopoweroff 0 powernap 0，然後 disablesleep 0。
#        sleep（閒置自動睡眠）設成 0（AC 和電池都是；原本電池是 1 分鐘），只有手動「睡眠」或闔上螢幕才會睡。
#   off：boot-args 從 config.plist.bak-hib2 還原（-v、debug=0x100 回來）；pmset disablesleep 1、hibernatemode 照 on 之前存下的值。
# 都要 sudo、要掛 ESP（boot-args 在 config.plist；改了要重開機才生效，pmset 立刻生效）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/power/hib-test.sh on'
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/power/hib-test.sh off'
# 出問題才用（現在不要執行）：CachyOS 還原 boot-args：sudo cp /boot/EFI/OC/config.plist.bak-hib2 /boot/EFI/OC/config.plist
set -u
OC=/tmp/int/EFI/OC
P=$OC/config.plist
BAK=$OC/config.plist.bak-hib2
SAVE=/Users/Shared/gpu/pmset-before-hib.txt
PB=/usr/libexec/PlistBuddy
K=":NVRAM:Add:7C436110-AB2A-4BBB-A880-FE41995C9F82:boot-args"
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
BA=$($PB -c "Print $K" "$P")

case "${1:-}" in
on)
  [ "$(sysctl -n debug.phxsleep_installed 2>/dev/null)" = 1 ] || { echo "PhxSleepPolicy 沒有搶到睡眠政策（debug.phxsleep_installed ≠ 1），不打開睡眠：它不在時睡眠會走 S3，這台醒不來"; exit 1; }
  [ -e "$BAK" ] && { echo "${BAK} 已經存在（on 跑過了？），停止"; exit 1; }
  cp "$P" "$BAK" && cmp -s "$P" "$BAK" || { echo "備份失敗，停止"; exit 1; }
  NEW=$(printf ' %s ' "$BA" | sed -E 's/ -v / /; s/ debug=0x100 / /; s/^ +//; s/ +$//')
  $PB -c "Set $K $NEW" "$P" && plutil -lint "$P" >/dev/null || { echo "改 config 失敗，從備份還原"; cp "$BAK" "$P"; exit 1; }
  # Wi-Fi 驅動（AirportMtkWlan）睡眠途中失敗會讓 MT7922 卡住，之後每次開機都在 mwx_load_firmware panic，要完全斷電才恢復
  # （2026-11-25）。測試期間停用它；off 從 bak-hib2 還原整份 config，會一起打開。
  N=$(plutil -extract Kernel.Add raw -o - "$P"); W=""
  for ((i = 0; i < N; i++)); do
    b=$($PB -c "Print :Kernel:Add:$i:BundlePath" "$P")
    case "$b" in *[Aa]irport*) [ "$($PB -c "Print :Kernel:Add:$i:Enabled" "$P")" = true ] && W="$W $i";; esac
  done
  set -- $W
  [ $# = 1 ] || { echo "啟用中的 Airport* kext 不是剛好一個（找到：${W:-無}），從備份還原、停止"; cp "$BAK" "$P"; exit 1; }
  echo "== 停用 Wi-Fi kext：Kernel.Add[$1] $($PB -c "Print :Kernel:Add:$1:BundlePath" "$P")（重開機後生效，測試期間沒有 Wi-Fi）"
  $PB -c "Set :Kernel:Add:$1:Enabled false" "$P" && plutil -lint "$P" >/dev/null || { echo "改 config 失敗，從備份還原"; cp "$BAK" "$P"; exit 1; }
  echo "== boot-args（重開機後生效）"
  echo "  原本：$BA"
  echo "  現在：$($PB -c "Print $K" "$P")"
  pmset -g custom > "$SAVE"
  echo "== pmset 原本的設定存在 ${SAVE}"
  pmset -a hibernatemode 25 standby 0 autopoweroff 0 powernap 0 sleep 0 && pmset -a disablesleep 0
  echo "== pmset 現在："
  pmset -g | grep -E 'SleepDisabled|hibernatemode|standby |autopoweroff|powernap| sleep '
  sync
  echo "✅ on 完成。重開機讓 boot-args 生效；之後闔上螢幕也會休眠。"
  ;;
off)
  pmset -a disablesleep 1
  if [ -f "$SAVE" ]; then
    hb=$(awk '/^Battery Power/{s="b"} /^AC Power/{s="c"} $1=="hibernatemode"{print s, $2}' "$SAVE")
    b=$(printf '%s\n' "$hb" | awk '$1=="b"{print $2}'); c=$(printf '%s\n' "$hb" | awk '$1=="c"{print $2}')
    [ -n "$b" ] && pmset -b hibernatemode "$b"; [ -n "$c" ] && pmset -c hibernatemode "$c"
    sl=$(awk '/^Battery Power/{s="b"} /^AC Power/{s="c"} $1=="sleep"{print s, $2}' "$SAVE")
    b=$(printf '%s\n' "$sl" | awk '$1=="b"{print $2}'); c=$(printf '%s\n' "$sl" | awk '$1=="c"{print $2}')
    [ -n "$b" ] && pmset -b sleep "$b"; [ -n "$c" ] && pmset -c sleep "$c"
  fi
  [ -f "$BAK" ] && { cp "$BAK" "$P" && cmp -s "$BAK" "$P" && mv "$BAK" "$BAK.used-$(date +%m%d-%H%M%S)" && echo "== config.plist 從 bak-hib2 還原（重開機後 -v、debug=0x100 回來）"; }
  echo "== pmset 現在："
  pmset -g | grep -E 'SleepDisabled|hibernatemode| sleep '
  sync
  echo "✅ off 完成：睡眠又關掉了"
  ;;
*) echo "用法：hib-test.sh on|off"; exit 2;;
esac
