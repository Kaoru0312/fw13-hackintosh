#!/bin/sh
# 用 Command Line Tools 編 VoodooI2CHID：VoodooI2C 2.9.1 內附的 HID 版本（a478fd6）+ i2c/patches/hid-reset-power-on.patch。
# 前置（i2c/src 不進 repo）：
#   git clone --depth 1 --branch v2.9.1 https://github.com/VoodooI2C/VoodooI2C.git i2c/src/VoodooI2C
#   git clone https://github.com/VoodooI2C/VoodooI2CHID.git "i2c/src/VoodooI2C/VoodooI2C Satellites/VoodooI2CHID"
#   git -C "…/VoodooI2CHID" checkout a478fd6 && git -C "…/VoodooI2CHID" apply i2c/patches/hid-reset-power-on.patch
#   MacKernelSDK：~/.mksdk
# 產出：i2c/build/VoodooI2CHID（只有 binary；安裝時保留 ESP 上現有的 Info.plist，因為那份有 IOPropertyMatch IOName=PIXA3854）
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="$HERE/src/VoodooI2C"
HID="$ROOT/VoodooI2C Satellites/VoodooI2CHID/VoodooI2CHID"
MKSDK=${MKSDK:-$HOME/.mksdk}
B="$HERE/build"
NAME=VoodooI2CHID
ID=com.alexandred.VoodooI2CHID
VER=1.0.0

[ -f "$HID/VoodooI2CHIDDevice.cpp" ] || { echo "找不到原始碼 $HID"; exit 1; }
grep -q "FW13PostResetPowerOn" "$HID/VoodooI2CHIDDevice.cpp" || { echo "補丁還沒套用，停止"; exit 1; }
rm -rf "$B"; mkdir -p "$B/obj"

cat > "$B/kmod_info.c" <<EOF
#include <mach/mach_types.h>
extern kern_return_t _start(kmod_info_t *, void *);
extern kern_return_t _stop(kmod_info_t *, void *);
__attribute__((visibility("default"))) KMOD_EXPLICIT_DECL(${ID}, "${VER}", _start, _stop)
__private_extern__ kmod_start_func_t *_realmain = 0;
__private_extern__ kmod_stop_func_t *_antimain = 0;
__private_extern__ int _kext_apple_cc = __APPLE_CC__;
EOF

COMMON="-arch x86_64 -mmacosx-version-min=10.12 -mkernel -fno-builtin -fno-common -nostdinc -I$MKSDK/Headers -DKERNEL -DKERNEL_PRIVATE -DDRIVER_PRIVATE -DAPPLE -DNeXT -O2 -Wno-everything"
CXX="$COMMON -std=gnu++11 -fapple-kext -fno-rtti -fno-exceptions"

clang -x c $COMMON -c "$B/kmod_info.c" -o "$B/obj/kmod_info.o"
OBJS="$B/obj/kmod_info.o"
find "$HID" -name '*.cpp' | while IFS= read -r f; do
    o="$B/obj/$(basename "$f" .cpp).o"
    clang++ $CXX -I"$HID" -I"$HID/Overrides" -I"$HID/Sensors" -c "$f" -o "$o"
done
clang++ -arch x86_64 -mmacosx-version-min=10.12 -nostdlib -Xlinker -kext -L"$MKSDK/Library/x86_64" -lkmod -lcc_kext \
  "$B"/obj/*.o -o "$B/$NAME"
echo "built $B/$NAME ($(git -C "$HID/.." rev-parse --short HEAD) + patch)"
