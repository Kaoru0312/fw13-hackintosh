#!/bin/sh
# 用 Command Line Tools 編 SimpleMtkBtPatcher（iussch/SimpleMtkBtFw 分支 tahoe-mt7922-ble-fix，PR flxxxxddd/SimpleMtkBtFw#3）。
# 前置：
#   git clone -b tahoe-mt7922-ble-fix https://github.com/iussch/SimpleMtkBtFw.git bt/src/SimpleMtkBtFw
#   Lilu SDK：Lilu-1.7.2-DEBUG.zip 解壓成 bt/src/SimpleMtkBtFw/Lilu.kext（跟 ESP 上的 Lilu 1.7.2 同版本）
#   MacKernelSDK：~/.mksdk（路徑不能有空格）
# 產出：bt/build/SimpleMtkBtPatcher.kext（Info.plist 以 1.1.0 release 為底，版本改成 1.1.0-lefix 方便辨認）
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC="$HERE/src/SimpleMtkBtFw"
MKSDK=${MKSDK:-$HOME/.mksdk}
LILU="$SRC/Lilu.kext/Contents/Resources"
B="$HERE/build"
OUT="$B/SimpleMtkBtPatcher.kext"
VER=1.1.0
NAME=SimpleMtkBtPatcher
ID=com.laobamac.SimpleMtkBtPatcher

[ -f "$SRC/$NAME/$NAME.cpp" ] || { echo "找不到原始碼 $SRC"; exit 1; }
[ -f "$LILU/Library/plugin_start.cpp" ] || { echo "找不到 Lilu SDK $LILU"; exit 1; }
rm -rf "$B"; mkdir -p "$OUT/Contents/MacOS"

cat > "$B/kmod_info.c" <<EOF
#include <mach/mach_types.h>
extern kern_return_t ${NAME}_kern_start(kmod_info_t *, void *);
extern kern_return_t ${NAME}_kern_stop(kmod_info_t *, void *);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(${ID}, "${VER}", ${NAME}_kern_start, ${NAME}_kern_stop)
__private_extern__ kmod_start_func_t *_realmain = ${NAME}_kern_start;
__private_extern__ kmod_stop_func_t *_antimain = ${NAME}_kern_stop;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOF

COMMON="-arch x86_64 -mmacosx-version-min=10.12 -mkernel -fno-builtin -fno-common -nostdinc -I$MKSDK/Headers -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -O2 -Wno-everything"
CXX="$COMMON -std=gnu++17 -fapple-kext -fno-rtti -fno-exceptions -I$LILU -DMODULE_VERSION=$VER -DPRODUCT_NAME=$NAME"

clang -x c $COMMON -c "$B/kmod_info.c" -o "$B/kmod_info.o"
clang++ $CXX -c "$SRC/$NAME/$NAME.cpp" -o "$B/$NAME.o"
clang++ $CXX -c "$LILU/Library/plugin_start.cpp" -o "$B/plugin_start.o"
clang++ -arch x86_64 -mmacosx-version-min=10.12 -nostdlib -Xlinker -kext -L"$MKSDK/Library/x86_64" -lkmod -lcc_kext \
  "$B/kmod_info.o" "$B/$NAME.o" "$B/plugin_start.o" -o "$OUT/Contents/MacOS/$NAME"

cp "$HERE/dl/$NAME.kext/Contents/Info.plist" "$OUT/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VER}-lefix" -c "Set :CFBundleVersion ${VER}" "$OUT/Contents/Info.plist"
echo "built $OUT ($(git -C "$SRC" rev-parse --short HEAD))"
