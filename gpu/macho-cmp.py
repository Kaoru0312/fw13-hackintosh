#!/usr/bin/env python3
"""比對兩個 x86_64 Mach-O：先列出不同的 byte，再判斷是否全部落在 LC_UUID 的 16 bytes 裡。
LC_UUID 是連結器依內容算的，內容改了 UUID 就跟著變；直接改二進位（topology-patch.py）則保留舊 UUID。
用法：python3 -I gpu/macho-cmp.py <a> <b>"""
import struct
import sys

a, b = (open(p, "rb").read() for p in sys.argv[1:3])


def uuid_range(d):
    magic, _, _, _, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", d, 0)
    if magic != 0xFEEDFACF:
        return None
    off = 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", d, off)
        if cmd == 0x1B:   # LC_UUID
            return off + 8, off + 24
        off += size
    return None


diff = [i for i in range(min(len(a), len(b))) if a[i] != b[i]]
r = uuid_range(a)
print(f"大小 {len(a)} / {len(b)}，不同 {len(diff)} bytes；LC_UUID 位於 {r and (hex(r[0]), hex(r[1]))}")
print(f"UUID：{a[r[0]:r[1]].hex() if r else '?'} / {b[r[0]:r[1]].hex() if r else '?'}")
outside = [i for i in diff if not (r and r[0] <= i < r[1])]
if len(a) == len(b) and not outside:
    print("✅ 除了 LC_UUID 之外逐 byte 相同（程式碼與資料完全一樣）")
    sys.exit(0)
print(f"✗ LC_UUID 以外還有 {len(outside)} bytes 不同，前幾個位移：{[hex(i) for i in outside[:10]]}")
sys.exit(1)
