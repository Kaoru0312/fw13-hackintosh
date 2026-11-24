#!/bin/bash
# 休眠第 3 步：PhxSleepPolicy.kext 放進 ESP、改 config.plist。睡眠仍然關著（pmset disablesleep 1 不動），所以裝完不會真的睡。
#   config.plist 的改動：
#   - Kernel.Add 最後面加 PhxSleepPolicy.kext（加在最後，不插在 Lilu 後面：repo 裡很多腳本用固定編號 [37]、[39]、[40]…）。
#     有沒有搶到睡眠政策開機後看 sysctl debug.phxsleep_installed（1 = 是我們的）。
#   - 停用 [47] HibernationFixup、[48] BootFBSleep（先前休眠嘗試留下的；PhxSleepPolicy 取代它們）。kext 檔案不刪。
#   - boot-args 拿掉 acpi=0x200000（同一次嘗試加的，意義不明）。
#   - Misc.Boot.HibernateSkipsPicker = true（只在有休眠映像時有作用：直接還原，不顯示 OpenCore 選單）。
#   - HibernateMode 維持 NVRAM（PhxSleepPolicy 把金鑰寫進 NVRAM）。
#   先備份 → 在副本上改 → 印出差異 → 確認無誤才蓋回去。
# 用法：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/power/hib-oc-install.sh'
# 先模擬（讀真的 ESP，只在暫存副本上改、印差異，不備份、不寫回）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; DRYRUN=1 bash /Users/kaoru/fw13-hackintosh/power/hib-oc-install.sh'
# DRYRUN=1 時不檢查 root／掛載，也可以 ESP=<假 ESP> 指到別處
#
# 出問題才用（現在不要執行）：
#   CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-hib1 /boot/EFI/OC/config.plist
#   （PhxSleepPolicy.kext 留在 Kexts 裡沒關係，config 沒列就不會載入）
set -u
R=/Users/kaoru/fw13-hackintosh
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
KEXT=${KEXT:-$R/power/sleeppolicy/build/PhxSleepPolicy.kext}
OC=$ESP/EFI/OC
P=$OC/config.plist
BAK=$OC/config.plist.bak-hib1
PB=/usr/libexec/PlistBuddy
GUID=7C436110-AB2A-4BBB-A880-FE41995C9F82

if [ "$DRYRUN" != 1 ]; then
  [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
  mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$KEXT/Contents/MacOS/PhxSleepPolicy" ] || { echo "找不到 ${KEXT}（先跑 power/sleeppolicy/build.sh）"; exit 1; }
[ -f "$P" ] || { echo "找不到 ${P}"; exit 1; }
[ "$DRYRUN" != 1 ] && [ -e "$BAK" ] && { echo "${BAK} 已經存在：這個腳本跑過了？停止（不蓋掉舊備份）"; exit 1; }

# 現況檢查：編號要跟 hib-check 看到的一樣
chk() { [ "$($PB -c "Print :Kernel:Add:$1:BundlePath" "$P" 2>/dev/null)" = "$2" ] || { echo "Kernel.Add[$1] 不是 $2，停止"; exit 1; }; }
chk 0 Lilu.kext
chk 37 PhxBringup.kext
chk 47 HibernationFixup.kext
chk 48 BootFBSleep.kext
N=$(plutil -extract Kernel.Add raw -o - "$P")
case "$N" in ''|*[!0-9]*) echo "讀不到 Kernel.Add 筆數，停止"; exit 1;; esac
for ((i = 0; i < N; i++)); do
  [ "$($PB -c "Print :Kernel:Add:$i:BundlePath" "$P")" = PhxSleepPolicy.kext ] && { echo "Kernel.Add[$i] 已經有 PhxSleepPolicy，停止"; exit 1; }
done
BA=$($PB -c "Print :NVRAM:Add:$GUID:boot-args" "$P")
echo "== 現在：Kernel.Add 共 $N 筆；boot-args：$BA"

if [ "$DRYRUN" != 1 ]; then
  cp "$P" "$BAK" && cmp -s "$P" "$BAK" || { echo "備份失敗，停止"; exit 1; }
  echo "  備份 → ${BAK}"
fi
T=$(mktemp)
cp "$P" "$T"
NEWBA=$(printf '%s' "$BA" | sed -E 's/(^| )acpi=0x[0-9a-fA-F]+//; s/^ +//')
$PB -c "Add :Kernel:Add:$N dict" \
    -c "Add :Kernel:Add:$N:Arch string Any" \
    -c "Add :Kernel:Add:$N:BundlePath string PhxSleepPolicy.kext" \
    -c "Add :Kernel:Add:$N:Comment string hibernation instead of the missing S3 (nullarc PR #20)" \
    -c "Add :Kernel:Add:$N:Enabled bool true" \
    -c "Add :Kernel:Add:$N:ExecutablePath string Contents/MacOS/PhxSleepPolicy" \
    -c "Add :Kernel:Add:$N:MaxKernel string" \
    -c "Add :Kernel:Add:$N:MinKernel string" \
    -c "Add :Kernel:Add:$N:PlistPath string Contents/Info.plist" \
    -c "Set :Kernel:Add:47:Enabled false" \
    -c "Set :Kernel:Add:48:Enabled false" \
    -c "Set :Misc:Boot:HibernateSkipsPicker true" \
    -c "Set :NVRAM:Add:$GUID:boot-args $NEWBA" \
    "$T" || { echo "PlistBuddy 失敗，原檔沒動"; rm -f "$T"; exit 1; }
plutil -lint "$T" >/dev/null || { echo "改完的副本不是合法 plist，原檔沒動"; rm -f "$T"; exit 1; }
echo "== 差異（左：原本，右：改完）"
diff <(plutil -p "$P") <(plutil -p "$T")

if [ "$DRYRUN" = 1 ]; then echo "== DRYRUN：不寫回，副本在 $T"; exit 0; fi
rm -rf "$OC/Kexts/PhxSleepPolicy.kext"
cp -R "$KEXT" "$OC/Kexts/PhxSleepPolicy.kext" || { echo "複製 kext 失敗，config 沒動"; rm -f "$T"; exit 1; }
cp "$T" "$P" && cmp -s "$T" "$P" || { echo "寫回失敗，從備份還原"; cp "$BAK" "$P"; exit 1; }
rm -f "$T"
mkdir -p /Users/kaoru/EFI-backup && cp "$BAK" /Users/kaoru/EFI-backup/config.plist.bak-hib1
sync
echo "== 完成。重開機後確認：sysctl debug.phxsleep_installed（1 = 搶到睡眠政策）；ioreg -rn IOPMrootDomain -d1 | grep IOSleepSupported"
echo "還原（CachyOS）：sudo cp /boot/EFI/OC/config.plist.bak-hib1 /boot/EFI/OC/config.plist"
