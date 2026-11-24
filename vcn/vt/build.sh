#!/bin/bash
# 編 H264VCNDecoder.bundle（VideoToolbox 解碼外掛）和命令列測試 vttest。只編譯，不安裝。
# 用法：bash /Users/kaoru/fw13-hackintosh/vcn/vt/build.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
H=$HERE/../h264
OUT=$HERE/build
rm -rf "$OUT" && mkdir -p "$OUT/H264VCNDecoder.bundle/Contents/MacOS"
SRC_CORE=("$HERE/h264vcn.c" "$H/h264_parse.c" "$H/vcn_h264_msg.c" "$H/h264_dpb.c")
FW="-framework CoreFoundation -framework CoreMedia -framework CoreVideo -framework VideoToolbox -framework IOKit"
clang -arch x86_64 -mmacosx-version-min=13.0 -O2 -Wall -Wextra -Wno-unused-parameter -fvisibility=hidden -bundle \
  "$HERE/H264VCNDecoder.c" "${SRC_CORE[@]}" $FW -o "$OUT/H264VCNDecoder.bundle/Contents/MacOS/H264VCNDecoder"
cp "$HERE/Info.plist" "$OUT/H264VCNDecoder.bundle/Contents/Info.plist"
codesign --force --sign - "$OUT/H264VCNDecoder.bundle"
nm -gU "$OUT/H264VCNDecoder.bundle/Contents/MacOS/H264VCNDecoder" | grep -q H264VCN_VTDecoder_CreateInstance || { echo "工廠函式沒有匯出"; exit 1; }
clang -arch x86_64 -mmacosx-version-min=13.0 -O2 -Wall -Wextra -Wno-unused-parameter "$HERE/vttest.c" "$H/h264_parse.c" \
  "$H/h264_stream.c" "$H/h264_dpb.c" "$H/vcn_h264_msg.c" "$H/md5.c" -framework CoreFoundation -framework CoreMedia \
  -framework CoreVideo -framework VideoToolbox -o "$OUT/vttest"
echo "built $OUT/H264VCNDecoder.bundle 與 $OUT/vttest"
