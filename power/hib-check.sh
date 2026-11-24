#!/bin/bash
# 休眠（S4）第 0 步：只讀檢查，什麼都不改（power/HIBERNATE-PLAN.md）。
#   - 系統睡眠支援（IOPMrootDomain、pmset、最近的睡眠被擋紀錄）
#   - 記憶體、磁碟空間（休眠映像檔 = 記憶體大小）
#   - NVRAM：boot-args、systemd-boot 的 Boot Loader Interface 變數、休眠相關變數
#   - OpenCore config.plist 相關欄位（要先掛 ESP 到 /tmp/int；沒掛就跳過）
#   - PhxAccel 的 Firebat EC 程式碼這次開機有沒有跑（kernel log）
# 用法（掛 ESP 和執行合成一行，ESP 會很快被自動卸載）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/power/hib-check.sh'
# 結果同時寫到 /Users/kaoru/fw13-hackintosh/power/hib-check-<時間>.txt
set -u
R=/Users/kaoru/fw13-hackintosh
OUT=$R/power/hib-check-$(date +%m%d-%H%M%S).txt
LOADER=4A67B082-0A4C-41CF-B6C7-440B29BB8C4F
CFG=/tmp/int/EFI/OC/config.plist
exec > >(tee "$OUT") 2>&1

echo "== $(date '+%F %T') hib-check（只讀）"
echo "== uptime：$(uptime)"
echo
echo "== 1. 系統睡眠支援"
ioreg -rn IOPMrootDomain -d1 -w0 | grep -E '"(IOSleepSupported|SleepDisabled|Supported Features|IOHibernateState|IOPMSystemSleepType|System Sleep Type|Hibernate)' || echo "  （IOPMrootDomain 沒有上面這些屬性）"
echo "-- pmset -g"
pmset -g
echo "-- pmset -g custom（有電池時分 AC／電池）"
pmset -g custom | grep -E -i 'hibernate|standby|autopoweroff|powernap|sleep|^[A-Z]'
echo "-- 最近的睡眠／休眠紀錄（pmset -g log，最後 15 筆）"
pmset -g log | grep -E -i 'prevented|unsupported|hibernat|Sleep  |Wake  |kPMPCI' | tail -15
echo
echo "== 2. 記憶體與磁碟"
echo "  hw.memsize = $(( $(sysctl -n hw.memsize) / 1048576 )) MiB"
df -h / /System/Volumes/Data 2>/dev/null
ls -la /private/var/vm 2>/dev/null
echo
echo "== 3. NVRAM"
echo "  boot-args：$(nvram boot-args 2>/dev/null | cut -f2-)"
for v in LoaderInfo LoaderEntrySelected LoaderEntryDefault LoaderEntries LoaderConfigTimeout LoaderFeatures; do
  x=$(nvram -x "$LOADER:$v" 2>/dev/null | plutil -extract "$LOADER:$v" raw -o - - 2>/dev/null)
  if [ -n "$x" ]; then
    # Boot Loader Interface 的字串是 UTF-16LE（base64）；印成文字
    printf '  %s = %s\n' "$v" "$(printf '%s' "$x" | base64 -D 2>/dev/null | iconv -f UTF-16LE -t UTF-8 2>/dev/null | tr '\0' '|')"
  else
    printf '  %s：讀不到\n' "$v"
  fi
done
nvram -p 2>/dev/null | grep -E -i 'hibernat|boot-image|boot-signature|IOHibernateRTC|phx' | cut -c1-120 || true
echo
echo "== 4. OpenCore config.plist（${CFG}）"
if [ -f "$CFG" ]; then
  k() { printf '  %-40s %s\n' "$1" "$(plutil -extract "$1" raw -o - "$CFG" 2>/dev/null || echo '（沒有這個欄位）')"; }
  k Misc.Boot.HibernateMode
  k Misc.Boot.HibernateSkipsPicker
  k Misc.Boot.ShowPicker
  k Misc.Boot.Timeout
  k Booter.Quirks.DiscardHibernateMap
  k UEFI.Quirks.RequestBootVarRouting
  k NVRAM.WriteFlash
  k NVRAM.LegacyOverwrite
  k Kernel.Quirks.ThirdPartyDrives
  echo "-- ACPI.Add"
  n=$(plutil -extract ACPI.Add raw -o - "$CFG" 2>/dev/null || echo 0)
  for ((i = 0; i < n; i++)); do
    printf '  [%d] %s enabled=%s\n' $i "$(plutil -extract ACPI.Add.$i.Path raw -o - "$CFG")" "$(plutil -extract ACPI.Add.$i.Enabled raw -o - "$CFG")"
  done
  echo "-- ACPI.Patch（只列 Comment）"
  n=$(plutil -extract ACPI.Patch raw -o - "$CFG" 2>/dev/null || echo 0)
  for ((i = 0; i < n; i++)); do
    printf '  [%d] %s enabled=%s\n' $i "$(plutil -extract ACPI.Patch.$i.Comment raw -o - "$CFG" 2>/dev/null)" "$(plutil -extract ACPI.Patch.$i.Enabled raw -o - "$CFG")"
  done
  echo "-- Kernel.Add 裡跟睡眠有關的（Lilu 位置、HibernationFixup）"
  n=$(plutil -extract Kernel.Add raw -o - "$CFG" 2>/dev/null || echo 0)
  for ((i = 0; i < n; i++)); do
    b=$(plutil -extract Kernel.Add.$i.BundlePath raw -o - "$CFG")
    case "$b" in Lilu*|*Hibernat*|*Sleep*|PhxBringup*) printf '  [%d] %s enabled=%s\n' $i "$b" "$(plutil -extract Kernel.Add.$i.Enabled raw -o - "$CFG")";; esac
  done
  echo "  Kernel.Add 共 $n 筆"
  ls /tmp/int/EFI/OC/Kexts | grep -i -E 'hibern|sleep' || echo "  EFI/OC/Kexts 裡沒有 Hibernation*／*Sleep* kext"
else
  echo "  沒掛 ESP（找不到 ${CFG}），這段跳過"
fi
echo
echo "== 5. PhxAccel 的 Firebat EC 程式碼（這次開機的 kernel log）"
log show --last boot --style compact --predicate 'eventMessage CONTAINS[c] "Firebat"' 2>/dev/null | grep -v '^Timestamp' | head -10
echo "  （有「Firebat EC init」＝ 開機時寫過實體位址 0xFE0B0400；有「fan regulator armed」＝ 之後每秒寫一次）"
echo "  PhxAccel：$(kextstat 2>/dev/null | grep -i phxaccel | awk '{print $6, $7}')；sha $(shasum -a 256 /Library/Extensions/PhxAccel.kext/Contents/MacOS/PhxAccel 2>/dev/null | cut -c1-8)"
echo
echo "== 6. 無線網卡（PR #20：MT7922 在睡眠中途失敗後可能要完全斷電才會恢復）"
ioreg -rc IOPCIDevice -w0 2>/dev/null | grep -E '"(vendor-id|device-id)" = <(c3140000|16790000|14c3|1679)' | head -4
system_profiler SPAirPortDataType 2>/dev/null | grep -E -m3 'Card Type|Firmware Version|Supported PHY'
echo
echo "== 結果存在 $OUT"
