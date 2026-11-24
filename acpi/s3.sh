#!/bin/bash
# 加入 SSDT-S3.aml（acpi/SSDT-S3.dsl）：只在 macOS 下、DSDT 沒有 \_S3 時補上，讓休眠流程不再被 kPMPCIUnsupported 擋下。
#   aml 在 Mac 上編：/Users/kaoru/fw13-hackintosh/acpi/iasl -vx 6142 /Users/kaoru/fw13-hackintosh/acpi/SSDT-S3.dsl
#   （這個腳本會自己編；ACPI.Add 加在最後，不動其他編號）
# 先模擬（只在暫存副本上改、印差異，不備份、不寫回）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; DRYRUN=1 bash /Users/kaoru/fw13-hackintosh/acpi/s3.sh'
# 正式：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/acpi/s3.sh'
# 出問題才用（現在不要執行）：CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-s3 /boot/EFI/OC/config.plist
set -u
HERE=/Users/kaoru/fw13-hackintosh/acpi
OC=/tmp/int/EFI/OC
P=$OC/config.plist
BAK=$P.bak-s3
PB=/usr/libexec/PlistBuddy
AML=SSDT-S3.aml
DRYRUN=${DRYRUN:-0}

[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
T=$(mktemp -d)
cp "$HERE/SSDT-S3.dsl" "$T/" && (cd "$T" && "$HERE/iasl" -vx 6142 SSDT-S3.dsl >/dev/null 2>&1) && [ -s "$T/$AML" ] || { echo "iasl 編譯失敗：$HERE/iasl -vx 6142 SSDT-S3.dsl"; exit 1; }
echo "== 編好 ${AML}（$(stat -f %z "$T/$AML") bytes）"
if $PB -c "Print :ACPI:Add" "$P" | grep -q "Path = ${AML}"; then echo "config 裡已經有 ${AML}，停止"; exit 1; fi
[ "$DRYRUN" != 1 ] && [ -e "$BAK" ] && { echo "${BAK} 已經存在，停止（不蓋掉舊備份）"; exit 1; }
N=$(plutil -extract ACPI.Add raw -o - "$P")
case "$N" in ''|*[!0-9]*) echo "讀不到 ACPI.Add 筆數，停止"; exit 1;; esac
cp "$P" "$T/config.plist"
$PB -c "Add :ACPI:Add:${N} dict" \
    -c "Add :ACPI:Add:${N}:Comment string _S3 for macOS when the DSDT hides it (Modern Standby); hibernation only" \
    -c "Add :ACPI:Add:${N}:Enabled bool true" \
    -c "Add :ACPI:Add:${N}:Path string ${AML}" "$T/config.plist" || { echo "PlistBuddy 失敗，原檔沒動"; exit 1; }
plutil -lint "$T/config.plist" >/dev/null || { echo "副本不是合法 plist，原檔沒動"; exit 1; }
echo "== 差異（左：原本，右：改完）"
diff <(plutil -p "$P") <(plutil -p "$T/config.plist")
if [ "$DRYRUN" = 1 ]; then echo "== DRYRUN：不寫回"; exit 0; fi
cp "$P" "$BAK" && cmp -s "$P" "$BAK" || { echo "備份失敗，停止"; exit 1; }
mkdir -p /Users/kaoru/EFI-backup && cp "$BAK" /Users/kaoru/EFI-backup/config.plist.bak-s3
cp "$T/$AML" "$OC/ACPI/$AML" || { echo "複製 aml 失敗，config 沒動"; exit 1; }
cp "$T/config.plist" "$P" && cmp -s "$T/config.plist" "$P" || { echo "寫回失敗，從備份還原"; cp "$BAK" "$P"; exit 1; }
sync
echo "== 完成：[${N}] ${AML}。備份 ${BAK}（~/EFI-backup 也有一份）。重開機後："
echo "   ioreg -p IOACPIPlane -lw0 -n FWS3 | grep _STA      （0x..0B：中間那個 byte 是 DAS3，最高的是 CNSB）"
echo "還原（CachyOS）：sudo cp /boot/EFI/OC/config.plist.bak-s3 /boot/EFI/OC/config.plist"
