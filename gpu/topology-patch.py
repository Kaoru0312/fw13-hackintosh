#!/usr/bin/env python3
"""把 nullarc v0.4.0 release 的 PhxBringup binary 裡「780M 預設拓撲表」換成 FW13 760M 的實測值。

為什麼改資料不改程式：
  - phx_find_topology() 對 HP(103c:8c6a) 以外的 0x15bf 一律回傳 &g_phx_780m_default，FW13 就是落到這張表。
  - repo 裡 nullarc-kext/ 的原始碼比 release 新（多了 IORWLock、client reaping、TLB flush），
    重編會一起帶進沒在這台驗證過的改動。只換這 128 bytes 的 const 資料，程式碼完全不動。
  - 這台只有一顆 GPU，780M 預設表不會再被別的裝置用到。

實測值：gpu-topology/fw13-760m.json（CachyOS 6.18.55 amdgpu AMDGPU_INFO_DEV_INFO，2026-11-21）。

用法：python3 -I gpu/topology-patch.py <release PhxBringup> <輸出檔>
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

RELEASE_SHA = "4a88035fd2ead990b8c44b638c9283d579b14d6ba4f0b48d78d6435a3a44a412"
VERSION, FLAGS = 1, 3  # PHX_TOPOLOGY_VERSION, CAPTURED | RUNTIME_READY


def table(vendor, device, rev, sv, sd, se, sa, cu_per_sh, rb, rb_mask, cu_active, bitmap):
    words = [VERSION, FLAGS, vendor, device, rev, sv, sd, se, sa, cu_per_sh, rb, rb_mask, cu_active]
    for row in bitmap:
        words += row
    words += [0, 0, 0]
    assert len(words) == 32
    return struct.pack("<32I", *words)


def valid(se, sa, cu_per_sh, rb, rb_mask, cu_active, bitmap):
    # 同 phx_topology_valid()
    cu_mask = 0xFFFFFFFF >> (32 - cu_per_sh)
    rb_all = 0xFFFFFFFF >> (32 - rb)
    if not (1 <= se <= 4 and 1 <= sa <= 4 and 1 <= cu_per_sh <= 32 and 1 <= rb <= 32 and rb_mask):
        return False
    if rb_mask & ~rb_all:
        return False
    count = 0
    for i in range(4):
        for j in range(4):
            m = bitmap[i][j]
            if m & ~cu_mask:
                return False
            if (i >= se or j >= sa) and m:
                return False
            count += bin(m).count("1")
    return count and count == cu_active


def main():
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    data = bytearray(src.read_bytes())
    sha = hashlib.sha256(data).hexdigest()
    if sha != RELEASE_SHA:
        sys.exit(f"不是 nullarc v0.4.0 release 的 PhxBringup（sha {sha}），停止")

    old = table(0x1002, 0x1900, 0xC8, 0, 0, 1, 2, 6, 4, 0xF, 12,
                [[0x3F, 0x3F, 0, 0], [0] * 4, [0] * 4, [0] * 4])
    hp = table(0x1002, 0x1900, 0xCA, 0x103C, 0x8C6A, 1, 2, 6, 4, 0xA, 8,
               [[0xF, 0xF, 0, 0], [0] * 4, [0] * 4, [0] * 4])

    j = json.loads((Path(__file__).resolve().parent.parent / "gpu-topology/fw13-760m.json").read_text())
    pci = j["pci"]
    bm = j["cu_bitmap"]
    args = (j["num_shader_engines"], j["num_shader_arrays_per_engine"], j["num_cu_per_sh"],
            j["num_rb_pipes"], j["enabled_rb_pipes_mask"], j["cu_active_number"], bm)
    if not valid(*args):
        sys.exit("JSON 的拓撲沒通過 phx_topology_valid 檢查，停止")
    if (pci["vendor"], pci["device"], pci["subvendor"], pci["subdevice"]) != (0x1002, 0x15BF, 0xF111, 0x0006):
        sys.exit(f"JSON 不是 FW13 的 GPU：{pci}")
    new = table(pci["vendor"], pci["device"], pci["revision"], pci["subvendor"], pci["subdevice"], *args)

    n_old, n_hp = data.count(old), data.count(hp)
    if n_old != 1 or n_hp != 1:
        sys.exit(f"找表失敗：780M 表 {n_old} 處、HP 760M 表 {n_hp} 處（各應為 1），停止")
    off = data.find(old)
    data[off:off + len(old)] = new
    dst.write_bytes(data)
    print(f"780M 預設表在 offset 0x{off:x}，已換成 FW13：CU {j['cu_active_number']}、"
          f"RB 遮罩 0x{j['enabled_rb_pipes_mask']:x}、CU 遮罩 {[hex(x) for x in bm[0][:2]]}")
    print(f"輸出 {dst}  sha256 {hashlib.sha256(data).hexdigest()}")
    diff = sum(1 for a, b in zip(src.read_bytes(), data) if a != b)
    print(f"改動 {diff} bytes（全部在這 128 bytes 內）")


if __name__ == "__main__":
    main()
