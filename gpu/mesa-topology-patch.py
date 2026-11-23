#!/usr/bin/env python3
"""把 nullarc v0.4.0 的 libvulkan_radeon.dylib（RADV）裡 canned "phoenix" 裝置資料換成 FW13 760M 實測值。

背景：
  - 這版 RADV 沒有 mesa-patches-phoenix 0007（向 PhxBringup 查 runtime topology），一律用
    Mesa src/amd/common/amdgpu_devices.c 的 "phoenix" 項目（780M：12 CU、cu_bitmap 0x3f/0x3f、RB 遮罩 0xf）。
  - 只改 drm_amdgpu_info_device 裡 cu_active_number、cu_bitmap[0][0..1]、enabled_rb_pipes_mask 這幾個 u32。
    其他欄位（device_id、GB_ADDR_CONFIG、記憶體、時脈…）都不動，跟 0007 的原則一樣（不從拓撲推其他值）。
  - 改完要 ad-hoc 重新簽章（原檔是 adhoc 簽章），由安裝腳本處理。

實測值：gpu-topology/fw13-760m.json。
用法：python3 -I gpu/mesa-topology-patch.py <原版 dylib> <輸出檔>
"""
import hashlib
import json
import struct
import sys
from pathlib import Path

ORIG_SHA = "1f2181d1183fa95f"  # 前 16 碼；完整值由安裝腳本記錄
FAMILY_GC_11_0_1 = 148


def devinfo_prefix(cu_active, bm0, bm1, rb_mask):
    # drm_amdgpu_info_device 開頭到 num_rb_pipes（uapi 順序）
    return (struct.pack("<8I", 0x15BF, 0x09, 0x0A, 0x04, FAMILY_GC_11_0_1, 1, 2, 99810)
            + struct.pack("<2Q", 2700000, 937000)
            + struct.pack("<2I", cu_active, 0)
            + struct.pack("<16I", bm0, bm1, *([0] * 14))
            + struct.pack("<2I", rb_mask, 4))


def main():
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    data = bytearray(src.read_bytes())
    sha = hashlib.sha256(data).hexdigest()
    if not sha.startswith(ORIG_SHA):
        sys.exit(f"不是 nullarc v0.4.0 的 libvulkan_radeon.dylib（sha {sha[:16]}…），停止")

    j = json.loads((Path(__file__).resolve().parent.parent / "gpu-topology/fw13-760m.json").read_text())
    if (j["num_shader_engines"], j["num_shader_arrays_per_engine"], j["num_cu_per_sh"], j["num_rb_pipes"]) != (1, 2, 6, 4):
        sys.exit("JSON 的 SE/SA/CU-per-SH/RB 數量跟 canned phoenix 不同，這個工具只改遮罩，停止")
    bm = j["cu_bitmap"]
    if any(bm[i][k] for i in range(4) for k in range(4) if not (i == 0 and k < 2)):
        sys.exit("cu_bitmap 在 SE0/SA0-1 以外有值，停止")
    if bin(bm[0][0]).count("1") + bin(bm[0][1]).count("1") != j["cu_active_number"]:
        sys.exit("cu_bitmap 位元數跟 cu_active_number 對不上，停止")

    old = devinfo_prefix(12, 0x3F, 0x3F, 0xF)
    new = devinfo_prefix(j["cu_active_number"], bm[0][0], bm[0][1], j["enabled_rb_pipes_mask"])
    n = data.count(old)
    if n != 1:
        sys.exit(f"canned phoenix 資料出現 {n} 處（應為 1），停止")
    off = data.find(old)
    data[off:off + len(old)] = new
    dst.write_bytes(data)
    diff = sum(1 for a, b in zip(src.read_bytes(), data) if a != b)
    print(f"canned phoenix dev info 在 offset 0x{off:x}；改成 CU {j['cu_active_number']}、"
          f"cu_bitmap 0x{bm[0][0]:x}/0x{bm[0][1]:x}、RB 遮罩 0x{j['enabled_rb_pipes_mask']:x}")
    print(f"改動 {diff} bytes；輸出 {dst}（尚未重新簽章）")


if __name__ == "__main__":
    main()
