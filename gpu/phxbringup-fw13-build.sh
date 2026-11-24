#!/bin/bash
# 用 v0.4.0-alpha 原始碼 + nullarc-port/patches/phxbringup-v040-*.patch（依檔名順序）編 FW13 版 PhxBringup。只編譯、不安裝、不用 sudo。
#   - 每次都從 nullarc-src/v040（phxbringup-repro.sh 下載、驗證過可重現 release）複製一份乾淨的到 nullarc-src/v040-fw13 再套補丁。
#   - 只套 01（拓撲表）時，結果應該跟「release + gpu/topology-patch.py」逐 byte 相同，也就是 ESP 上現在用的那份。
# 用法：bash /Users/kaoru/fw13-hackintosh/gpu/phxbringup-fw13-build.sh [只套到第幾號，預設全部]
set -u
R=/Users/kaoru/fw13-hackintosh
SRC=$R/nullarc-src/v040
W=$R/nullarc-src/v040-fw13
MKSDK=$R/MacKernelSDK
UPTO=${1:-99}
REL=$R/nullarc-release/nullarc-0.4.0-alpha/EFI/OC/Kexts/PhxBringup.kext/Contents/MacOS/PhxBringup

[ -d "$SRC/.git" ] || { echo "先跑 gpu/phxbringup-repro.sh（下載並驗證 v0.4.0 原始碼）"; exit 1; }
rm -rf "$W" && cp -R "$SRC" "$W" && rm -rf "$W/src/phxbringup/build"
n=0
for P in "$R"/nullarc-port/patches/phxbringup-v040-*.patch; do
  num=$(basename "$P" | sed 's/phxbringup-v040-\([0-9]*\)-.*/\1/')
  [ "$((10#$num))" -le "$UPTO" ] || continue
  echo "== 套 $(basename "$P")"
  (cd "$W" && patch -p1 --no-backup-if-mismatch < "$P") || { echo "補丁套不上，停止"; exit 1; }
  n=$((n + 1))
done
sh "$W/src/phxbringup/build.sh" "$MKSDK" 2>&1 | grep -v 'Wshadow\|shadows a field\|previous\|declaration is here\|^ *[0-9]* |\|^ *| *\^\|warnings generated' || true
BIN=$W/src/phxbringup/build/PhxBringup.kext/Contents/MacOS/PhxBringup
[ -f "$BIN" ] || { echo "編譯失敗"; exit 1; }
GOT=$(shasum -a 256 "$BIN" | cut -d' ' -f1)
echo "== 套了 ${n} 個補丁，編出來：${GOT}（$(stat -f %z "$BIN") bytes）"
if [ "$UPTO" = 1 ] && [ -f "$REL" ]; then
  T=$(mktemp)
  python3 -I "$R/gpu/topology-patch.py" "$REL" "$T" >/dev/null || { echo "topology-patch.py 失敗"; exit 1; }
  WANT=$(shasum -a 256 "$T" | cut -d' ' -f1)
  echo "== release + topology-patch.py：${WANT}"
  if [ "$GOT" = "$WANT" ]; then echo "✅ 逐 byte 相同：原始碼版拓撲表 = ESP 上現在用的二進位"; else
    echo "✗ 不同：$(cmp -l "$BIN" "$T" | wc -l | tr -d ' ') bytes"; cmp -l "$BIN" "$T" | head -10; fi
  rm -f "$T"
fi
echo "輸出：$W/src/phxbringup/build/PhxBringup.kext"
