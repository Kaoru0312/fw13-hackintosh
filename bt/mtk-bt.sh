#!/bin/bash
# RZ616 藍牙（USB 0e8d:e616，「Wireless_Device」，裝置類別 EF/02/01）：
#   1. BlueToolFixup 換成 2.7.2，並啟用 config 裡原本就有但停用的那一項（編號不變）。
#   2. 加入 SimpleMtkBtFw 1.1.0（laobamac，內含 BT_RAM_CODE_MT7922_1_1_hdr.bin），在 ESP 上的 Info.plist
#      加一條 personality 比對 0e8d:e616（IOProbeScore 94000，比照 TongFang 對 0608 的做法，搶在 AppleUSBHostCompositeDevice 前面）。
#      原本的通用 personality 要求 bDeviceClass 224，FW13 是 239，比對不到。
#   3. 加入 SimpleMtkBtPatcher 1.1.0（Lilu 外掛）。
#   兩個新 kext 加在 Kernel.Add 最後。kext 來源：kevin8717/TongFang-7840HS-Hackintosh（6758dda），repo 裡只放在 bt/dl/（不進 git）。
#
# 用法（一行）：
#   sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/bt/mtk-bt.sh'
#
# 出問題才用（現在不要執行）：
#   macOS：sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; cp /tmp/int/EFI/OC/config.plist.bak-1121i /tmp/int/EFI/OC/config.plist'
#   CachyOS：sudo cp /boot/EFI/OC/config.plist.bak-1121i /boot/EFI/OC/config.plist
#   （BlueToolFixup 資料夾被換成 2.7.2；還原 config 後它是停用狀態，不影響）
#
# 測試用：DRYRUN=1 ESP=<假 ESP 資料夾> bash mtk-bt.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ESP=${ESP:-/tmp/int}
DRYRUN=${DRYRUN:-0}
OC=$ESP/EFI/OC
P=$OC/config.plist
PB=/usr/libexec/PlistBuddy
TAG=1121i
# macOS 的 /bin/bash 是 3.2，沒有關聯陣列，所以用「名稱=雜湊」字串
SHAS="BlueToolFixup=f3244382a43866138ff449b14f1e54fb069ad3e4b14cbc753858650efdbbce52
SimpleMtkBtFw=8cb389edefb0ee68ef99fe984ae945f8c9cfcc33239592c6283b7e4cdc9fe237
SimpleMtkBtPatcher=716caec563cea696d5c4817b8377c523dadfe43150fe934c44b678c2f0cac623"
PERS=":IOKitPersonalities:SimpleMtkBtFw_MT7922_0e8d_e616"

if [ "$DRYRUN" != 1 ]; then
    [ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }
    mount | grep -q "/dev/disk0s1 on /private/tmp/int" || { echo "ESP 沒有掛在 /tmp/int"; exit 1; }
fi
[ -f "$P" ] || { echo "找不到 $P"; exit 1; }
for line in $SHAS; do
    k=${line%%=*}; h=${line#*=}
    [ "$(shasum -a 256 "$HERE/dl/$k.kext/Contents/MacOS/$k" | awk '{print $1}')" = "$h" ] || { echo "$k binary 的 SHA-256 不符，停止"; exit 1; }
done
for k in SimpleMtkBtFw SimpleMtkBtPatcher; do
    $PB -c "Print :Kernel:Add" "$P" | grep -q "BundlePath = $k.kext" && { echo "config 裡已經有 ${k}，停止"; exit 1; }
done
[ -e "$P.bak-${TAG}" ] && { echo "config.plist.bak-${TAG} 已存在，停止（可能已經跑過）"; exit 1; }

N=$($PB -c "Print :Kernel:Add" "$P" | grep -c "BundlePath")
BT=""
for ((i=0; i<N; i++)); do
    [ "$($PB -c "Print :Kernel:Add:${i}:BundlePath" "$P")" = "BlueToolFixup.kext" ] && { BT=$i; break; }
done

echo "== 1. 備份"
cp "$P" "$P.bak-${TAG}"
if [ "$DRYRUN" != 1 ]; then
    mkdir -p /Users/kaoru/EFI-backup
    cp "$P" "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    chown kaoru:staff "/Users/kaoru/EFI-backup/config.plist.bak-${TAG}"
    echo "  config.plist.bak-${TAG}（ESP 與 ~/EFI-backup 各一份）"
else
    echo "  config.plist.bak-${TAG}"
fi

echo "== 2. 放入 kext"
for k in BlueToolFixup SimpleMtkBtFw SimpleMtkBtPatcher; do
    rm -rf "$OC/Kexts/$k.kext"
    ditto "$HERE/dl/$k.kext" "$OC/Kexts/$k.kext"
    echo "  $k.kext $($PB -c 'Print :CFBundleVersion' "$OC/Kexts/$k.kext/Contents/Info.plist")"
done

echo "== 3. SimpleMtkBtFw 加 0e8d:e616 比對"
KPL=$OC/Kexts/SimpleMtkBtFw.kext/Contents/Info.plist
$PB -c "Add ${PERS} dict" \
    -c "Add ${PERS}:CFBundleIdentifier string com.laobamac.SimpleMtkBtFw" \
    -c "Add ${PERS}:IOClass string SimpleMtkBtFw" \
    -c "Add ${PERS}:IOProviderClass string IOUSBHostDevice" \
    -c "Add ${PERS}:idVendor integer 3725" \
    -c "Add ${PERS}:idProduct integer 58902" \
    -c "Add ${PERS}:IOProbeScore integer 94000" "$KPL"
plutil -lint "$KPL"
diff <(plutil -convert xml1 -o - "$HERE/dl/SimpleMtkBtFw.kext/Contents/Info.plist") <(plutil -convert xml1 -o - "$KPL") || true

echo "== 4. config.plist Kernel.Add"
if [ -n "$BT" ]; then
    $PB -c "Set :Kernel:Add:${BT}:Enabled true" "$P"
    echo "  [${BT}] BlueToolFixup → Enabled=true（其他欄位不動）"
else
    $PB -c "Add :Kernel:Add:${N} dict" \
        -c "Add :Kernel:Add:${N}:Arch string x86_64" \
        -c "Add :Kernel:Add:${N}:BundlePath string BlueToolFixup.kext" \
        -c "Add :Kernel:Add:${N}:Comment string BrcmPatchRAM BlueToolFixup 2.7.2" \
        -c "Add :Kernel:Add:${N}:Enabled bool true" \
        -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/BlueToolFixup" \
        -c "Add :Kernel:Add:${N}:MaxKernel string" \
        -c "Add :Kernel:Add:${N}:MinKernel string 21.0.0" \
        -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"
    echo "  [${N}] BlueToolFixup（新增）"
    N=$((N+1))
fi
for k in SimpleMtkBtFw SimpleMtkBtPatcher; do
    $PB -c "Add :Kernel:Add:${N} dict" \
        -c "Add :Kernel:Add:${N}:Arch string x86_64" \
        -c "Add :Kernel:Add:${N}:BundlePath string $k.kext" \
        -c "Add :Kernel:Add:${N}:Comment string $k 1.1.0 (laobamac) RZ616 Bluetooth" \
        -c "Add :Kernel:Add:${N}:Enabled bool true" \
        -c "Add :Kernel:Add:${N}:ExecutablePath string Contents/MacOS/$k" \
        -c "Add :Kernel:Add:${N}:MaxKernel string" \
        -c "Add :Kernel:Add:${N}:MinKernel string" \
        -c "Add :Kernel:Add:${N}:PlistPath string Contents/Info.plist" "$P"
    echo "  [${N}] $k"
    N=$((N+1))
done

echo "== 檢查"
plutil -lint "$P"
echo "  [0] $($PB -c 'Print :Kernel:Add:0:BundlePath' "$P")（Lilu 要在最前面）"
echo "  [37] $($PB -c 'Print :Kernel:Add:37:BundlePath' "$P")（未動）"
echo "== config 與備份的差異"
diff <(plutil -convert xml1 -o - "$P.bak-${TAG}") <(plutil -convert xml1 -o - "$P") || true
echo ""
echo "完成。卸載 ESP（sudo diskutil unmount /tmp/int）後重開機。"
echo "開機後檢查：kextstat | grep -i -E 'mtk|bluetool' ；系統設定 → 藍牙 有沒有出現。"
