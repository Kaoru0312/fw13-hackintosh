#!/bin/bash
# 把 H264VCNDecoder.bundle 放進「密封的系統磁碟區」的 /System/Library/Video/Plug-Ins。
#   /System/Library/Video 沒有 firmlink（/usr/share/firmlinks 只有 CoreTypes.bundle/Contents/Library，nullarc 的 Metal 外掛放在那裡），
#   所以要照 OCLP 這類工具修改系統的標準流程：把系統磁碟區（不是開機用的快照）另外掛成可寫入 → 放檔案 →
#   bless --create-snapshot 建一個新的系統快照 → 重開機後從新快照開機。
#   前提（2026-11-24 已確認）：Authenticated Root disabled、FileVault Off。
#
# 用法：
#   sudo bash rootpatch.sh --check              只讀：列出開機快照、對應的系統磁碟區、快照清單（什麼都不改）
#   sudo bash rootpatch.sh --install --yes      掛載、複製外掛、建新快照（重開機後生效）
#   sudo bash rootpatch.sh --remove --yes       掛載、刪掉外掛、建新快照
# 出問題才用（現在不要執行）：
#   回到 Apple 原本的密封快照（拿掉所有對系統磁碟區的修改；nullarc 的東西在 Data 磁碟區，不受影響）：
#     sudo bless --mount / --bootefi --last-sealed-snapshot   然後重開機
#   如果 macOS 開不了機：開機選單選 macOS Recovery → 終端機 → 同上（--mount 改成系統磁碟區的路徑，如 /Volumes/Macintosh\ HD）
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
MNT=/private/var/tmp/fw13-sysvol
BUNDLE=$HERE/build/H264VCNDecoder.bundle
MODE=${1:-}; YES=${2:-}
[ "$(id -u)" = 0 ] || { echo "請用 sudo 執行"; exit 1; }

NODE=$(diskutil info / | awk -F': *' '/Device Node/{print $2}')
SNAP=$(diskutil info / | awk -F': *' '/APFS Snapshot:/{print $2}')
VOL=$(echo "$NODE" | sed -E 's/s[0-9]+$//')
echo "== 開機用的：${NODE}（APFS Snapshot: ${SNAP:-?}）"
echo "== 對應的系統磁碟區：${VOL}"
echo "== authenticated-root：$(csrutil authenticated-root status | sed 's/.*: //')；FileVault：$(fdesetup status)"
diskutil apfs listSnapshots "$VOL" 2>/dev/null | grep -E 'Name|XID|Purgeable|Limiting' | head -12
[ "$SNAP" = "Yes" ] || { echo "目前不是從快照開機，跟預期不同，停止"; exit 1; }
csrutil authenticated-root status | grep -q disabled || { echo "authenticated-root 沒關，停止"; exit 1; }
fdesetup status | grep -q 'Off' || { echo "FileVault 開著，停止"; exit 1; }
[ "$MODE" = "--check" ] && { echo "（--check：什麼都沒改）"; exit 0; }
[ "$MODE" = "--install" ] || [ "$MODE" = "--remove" ] || { echo "用法：--check | --install --yes | --remove --yes"; exit 2; }
[ "$YES" = "--yes" ] || { echo "要加 --yes 才會改系統磁碟區"; exit 2; }
[ "$MODE" = "--remove" ] || [ -f "$BUNDLE/Contents/MacOS/H264VCNDecoder" ] || { echo "先跑 vcn/vt/build.sh"; exit 1; }

mkdir -p "$MNT"
mount | grep -q " on $MNT " || mount -o nobrowse -t apfs "$VOL" "$MNT" || { echo "掛載 ${VOL} 失敗，停止（什麼都沒改）"; exit 1; }
D=$MNT/System/Library/Video/Plug-Ins
[ -d "$D" ] || { echo "掛載點裡找不到 ${D}，卸載後停止"; umount "$MNT"; exit 1; }
touch "$D/.fw13-write-test" 2>/dev/null && rm -f "$D/.fw13-write-test" || { echo "掛載點還是唯讀，卸載後停止"; umount "$MNT"; exit 1; }
if [ "$MODE" = "--install" ]; then
  rm -rf "$D/H264VCNDecoder.bundle"
  ditto "$BUNDLE" "$D/H264VCNDecoder.bundle" && chown -R root:wheel "$D/H264VCNDecoder.bundle" && chmod -R go-w "$D/H264VCNDecoder.bundle" \
    || { echo "複製失敗，卸載後停止（還沒建快照，重開機後一切照舊）"; umount "$MNT"; exit 1; }
  echo "  已放入 $D/H264VCNDecoder.bundle"
else
  rm -rf "$D/H264VCNDecoder.bundle" && echo "  已刪除 $D/H264VCNDecoder.bundle"
fi
echo "== 建立新的系統快照（bless --create-snapshot）"
if bless --folder "$MNT/System/Library/CoreServices" --bootefi --create-snapshot; then
  echo "  完成。重開機後從新快照開機。"
else
  echo "  ✗ bless 失敗：沒有建立新快照，目前開機的快照沒變，重開機後一切照舊"
fi
umount "$MNT" 2>/dev/null || diskutil unmount "$MNT" 2>/dev/null
diskutil apfs listSnapshots "$VOL" 2>/dev/null | grep -E 'Name' | head -6
echo "回到 Apple 原本的快照（出問題才用）：sudo bless --mount / --bootefi --last-sealed-snapshot"
