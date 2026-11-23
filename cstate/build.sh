#!/bin/sh
# Builds AMDCState.kext with the Command Line Tools. Usage: ./build.sh <MacKernelSDK path without spaces>
set -eu
MKSDK=${1:?usage: build.sh <MacKernelSDK>}
HERE=$(cd "$(dirname "$0")" && pwd)
OUT="$HERE/build/AMDCState.kext"
rm -rf "$HERE/build"; mkdir -p "$OUT/Contents/MacOS"
CFLAGS="-arch x86_64 -mmacosx-version-min=11.0 -mkernel -fno-builtin -fno-common -nostdinc -I$MKSDK/Headers -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -Os -Wall"
clang -x c $CFLAGS -c "$HERE/kmod_info.c" -o "$HERE/build/kmod_info.o"
clang++ $CFLAGS -std=c++17 -fapple-kext -fno-rtti -fno-exceptions -c "$HERE/AMDCState.cpp" -o "$HERE/build/AMDCState.o"
clang++ -arch x86_64 -mmacosx-version-min=11.0 -nostdlib -Xlinker -kext -L"$MKSDK/Library/x86_64" -lkmodc++ -lkmod -lcc_kext \
  "$HERE/build/kmod_info.o" "$HERE/build/AMDCState.o" -o "$OUT/Contents/MacOS/AMDCState"
cp "$HERE/Info.plist" "$OUT/Contents/Info.plist"
echo "built $OUT"
