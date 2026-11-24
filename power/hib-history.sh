#!/bin/bash
# 休眠第 0 步之二：找出先前那次休眠嘗試（BootFBSleep、acpi=0x200000、PhxAccel d9c4d407）留下的痕跡。只讀，什麼都不改。
#   - 原始碼：BootFBSleep*.cpp、display/dscl/（含 Claude 的 scratch-workspaces）
#   - 系統紀錄：pmset 睡眠／喚醒紀錄、11-22 之後的 panic／Sleep Wake Failure 報告、kernel log 裡 BootFBSleep 的訊息
#   - ESP：config.plist 各個備份的時間、boot-args、有沒有 BootFBSleep（找出 acpi=0x200000 是哪一版加的）
# 用法：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/power/hib-history.sh'
# 結果同時寫到 /Users/kaoru/fw13-hackintosh/power/hib-history-<時間>.txt
set -u
R=/Users/kaoru/fw13-hackintosh
OUT=$R/power/hib-history-$(date +%m%d-%H%M%S).txt
exec > >(tee "$OUT") 2>&1
echo "== $(date '+%F %T') hib-history（只讀）"

echo; echo "== 1. 原始碼"
find /Users/kaoru -xdev \( -iname 'BootFBSleep*' -o -iname '*bootfbsleep*' -o -iname 'PhxSleep*' \) \
  ! -path '*/LiluDEBUG*' ! -path '*/.Trash/*' 2>/dev/null | head -30
echo "-- display/ 裡沒 commit 的"
for d in "$R/display/dscl" "$R/display/modetry" "$R/display/cgsmodes"; do
  [ -e "$d" ] && { echo "  $d"; find "$d" -maxdepth 2 -type f -exec stat -f '    %Sm %z %N' {} \; 2>/dev/null | head -20; }
done
echo "-- scratch-workspaces 裡跟睡眠／DSCL 有關的檔案"
find "/Users/kaoru/Library/Application Support/Claude" -xdev -type f \
  \( -iname '*sleep*' -o -iname '*hibern*' -o -iname '*dscl*' -o -iname '*scale*' -o -iname 'HANDOFF*' \) 2>/dev/null \
  | grep -v -i -E '/node_modules/|\.png$|/LiluDEBUG' | head -30

echo; echo "== 2. pmset 睡眠／喚醒紀錄（11-22 之後）"
pmset -g log 2>/dev/null | grep -E '^2026-11-2[2-4]' | grep -E -i ' (Sleep|Wake|DarkWake|Failure|Hibernate)[ :]|Sleep Wake failure|hibernat' | head -40

echo; echo "== 3. 診斷報告（11-22 之後的 panic、Sleep Wake Failure）"
ls -la /Library/Logs/DiagnosticReports 2>/dev/null | grep -E 'Kernel|panic|Sleep|Wake|hibern' | grep -E '11月 2[2-4]|2026-11-2[2-4]' | head -20

echo; echo "== 4. kernel log 裡 BootFBSleep 的訊息（11-22 起，只取前 40 行）"
log show --start '2026-11-22 00:00:00' --style compact \
  --predicate 'eventMessage CONTAINS "BootFBSleep" OR eventMessage CONTAINS[c] "hibernate"' 2>/dev/null \
  | grep -v '^Timestamp' | head -40

echo; echo "== 5. ESP：config.plist 各版本的 boot-args 與 BootFBSleep"
O=/tmp/int/EFI/OC
if [ -d "$O" ]; then
  for f in $(ls -tr "$O"/config.plist* 2>/dev/null); do
    ba=$(plutil -extract 'NVRAM.Add.7C436110-AB2A-4BBB-A880-FE41995C9F82.boot-args' raw -o - "$f" 2>/dev/null)
    hb=$(plutil -extract Misc.Boot.HibernateMode raw -o - "$f" 2>/dev/null)
    bf=$(grep -c BootFBSleep "$f" 2>/dev/null)
    hf=$(grep -c HibernationFixup "$f" 2>/dev/null)
    a=$(printf '%s' "$ba" | grep -o 'acpi=[^ ]*')
    printf '  %s  %-28s HibernateMode=%-6s BootFBSleep=%s HibernationFixup=%s %s\n' "$(stat -f '%Sm' "$f")" "$(basename "$f")" "$hb" "$bf" "$hf" "${a:-（沒有 acpi=）}"
  done
  echo "-- Kexts 裡的 BootFBSleep 各版本"
  for k in "$O"/Kexts/BootFBSleep.kext*; do
    printf '  %s  %s  %s\n' "$(stat -f '%Sm' "$k/Contents/MacOS/BootFBSleep" 2>/dev/null)" "$(basename "$k")" \
      "$(plutil -extract CFBundleShortVersionString raw -o - "$k/Contents/Info.plist" 2>/dev/null)"
  done
else
  echo "  沒掛 ESP，這段跳過"
fi
echo; echo "== 結果存在 ${OUT}"
