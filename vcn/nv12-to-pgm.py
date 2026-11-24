#!/usr/bin/env python3
"""把 vcnctl decodetest 存的 NV12 畫面的亮度（Y）平面轉成 PGM 灰階圖，macOS 的「預覽程式」可以直接開。
用法：python3 vcn/nv12-to-pgm.py <輸入.nv12> <輸出.pgm> [寬 864] [高 480] [行距 1024]"""
import sys
src, dst = sys.argv[1], sys.argv[2]
w, h, pitch = (int(x) for x in (sys.argv[3:6] + ["864", "480", "1024"][len(sys.argv[3:6]):]))
data = open(src, "rb").read()
rows = b"".join(data[y * pitch:y * pitch + w] for y in range(h))
open(dst, "wb").write(b"P5\n%d %d\n255\n" % (w, h) + rows)
print(f"{dst}: {w}x{h} 灰階（只有 Y 平面）")
