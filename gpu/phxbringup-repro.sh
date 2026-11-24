#!/bin/bash
# 重編 PhxBringup 第 0 步：用 nullarc v0.4.0-alpha 標籤的原始碼在本機編一次，確認跟 release 二進位逐 byte 相同。
#   - 只編譯、不安裝、不用 sudo；只寫入 nullarc-src/v040/（gitignore）。
#   - 通過了，之後改 kext（硬解介面、GFXOFF）才能確定「差異只來自我們的修改」。
#   - release 的 sha256 取自 gpu/topology-patch.py 的 RELEASE_SHA（ESP 上用的是這份再改拓撲表 10 bytes）。
# 用法：bash /Users/kaoru/fw13-hackintosh/gpu/phxbringup-repro.sh
set -u
R=/Users/kaoru/fw13-hackintosh
N=$R/nullarc-src/v040
MKSDK=$R/MacKernelSDK
WANT=4a88035fd2ead990b8c44b638c9283d579b14d6ba4f0b48d78d6435a3a44a412

[ -d "$MKSDK/Headers" ] || { echo "找不到 $MKSDK/Headers"; exit 1; }
if [ ! -d "$N/.git" ]; then
  echo "== 下載 nullarc v0.4.0-alpha 原始碼到 ${N}"
  git clone -q --depth 1 --branch v0.4.0-alpha https://github.com/luuumi-dev/nullarc.git "$N" || { echo "git clone 失敗"; exit 1; }
fi
echo "== 原始碼：$(git -C "$N" describe --tags 2>/dev/null) $(git -C "$N" rev-parse --short HEAD)"
echo "== 編譯器：$(clang --version | head -1)"
sh "$N/src/phxbringup/build.sh" "$MKSDK" || { echo "編譯失敗"; exit 1; }
BIN=$N/src/phxbringup/build/PhxBringup.kext/Contents/MacOS/PhxBringup
GOT=$(shasum -a 256 "$BIN" | cut -d' ' -f1)
echo "== 編出來：${GOT}（$(stat -f %z "$BIN") bytes）"
echo "== release：$WANT"
REL=$(find "$R/nullarc-release" -path '*PhxBringup.kext/Contents/MacOS/PhxBringup' 2>/dev/null | head -1)
[ -n "$REL" ] && echo "== release 檔：${REL}（$(stat -f %z "$REL") bytes，sha $(shasum -a 256 "$REL" | cut -c1-16)…）"
if [ "$GOT" = "$WANT" ]; then
  echo "✅ 逐 byte 相同：本機可以重現 release 二進位"
else
  echo "✗ 不同"
  if [ -n "$REL" ]; then
    echo "  不同的 byte 數：$(cmp -l "$BIN" "$REL" 2>/dev/null | wc -l | tr -d ' ')（cmp 的前 10 筆：位移 我們 release，八進位）"
    cmp -l "$BIN" "$REL" 2>&1 | head -10
  fi
fi
