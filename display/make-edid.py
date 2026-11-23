#!/usr/bin/env python3
"""產生 FW13 面板的合成 EDID（128 bytes），內容跟 phxaccel-port/accel/phxfb.cpp 的 getDDCBlock() 一致：
vendor "FRW"、product 1、EDID 1.4、285×190 mm、native timing 照 nativeTiming()（2256×1504，H total 2536、V total 1549、60 Hz，
H sync offset 48 / width 32、V sync offset 3 / width 6）、名稱 "Framework 13"。
用法：python3 -I display/make-edid.py <輸出 .bin>
"""
import sys

W, H, HT, VT, MHZ = 2256, 1504, 2536, 1549, 60000
HMM, VMM = 285, 190


def edid():
    e = bytearray(128)
    e[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
    mfg = ((ord("F") - 64) << 10) | ((ord("R") - 64) << 5) | (ord("W") - 64)
    e[8], e[9] = mfg >> 8, mfg & 0xFF
    e[10], e[11] = 0x01, 0x00
    e[16], e[17] = 1, 2023 - 1990
    e[18], e[19] = 1, 4
    e[20] = 0xA5
    e[21], e[22] = 29, 19
    e[23] = 120
    e[24] = 0x02
    e[25:35] = bytes([0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])
    for i in range(38, 54):
        e[i] = 0x01
    hb, vb = HT - W, VT - H
    hso, hsw, vso, vsw = 48, 32, 3, 6
    pc = (HT * VT * MHZ // 1000) // 10000
    d = 54
    e[d + 0], e[d + 1] = pc & 0xFF, (pc >> 8) & 0xFF
    e[d + 2], e[d + 3] = W & 0xFF, hb & 0xFF
    e[d + 4] = (((W >> 8) & 0xF) << 4) | ((hb >> 8) & 0xF)
    e[d + 5], e[d + 6] = H & 0xFF, vb & 0xFF
    e[d + 7] = (((H >> 8) & 0xF) << 4) | ((vb >> 8) & 0xF)
    e[d + 8], e[d + 9] = hso & 0xFF, hsw & 0xFF
    e[d + 10] = ((vso & 0xF) << 4) | (vsw & 0xF)
    e[d + 11] = (((hso >> 8) & 3) << 6) | (((hsw >> 8) & 3) << 4) | (((vso >> 4) & 3) << 2) | ((vsw >> 4) & 3)
    e[d + 12], e[d + 13] = HMM & 0xFF, VMM & 0xFF
    e[d + 14] = (((HMM >> 8) & 0xF) << 4) | ((VMM >> 8) & 0xF)
    e[d + 17] = 0x1E
    n = 72
    e[n + 3] = 0xFC
    e[n + 5:n + 18] = b"Framework 13\n"
    e[90 + 3] = 0x10
    e[108 + 3] = 0x10
    e[127] = (-sum(e[:127])) & 0xFF
    assert sum(e) & 0xFF == 0
    return bytes(e)


if __name__ == "__main__":
    out = sys.argv[1]
    data = edid()
    open(out, "wb").write(data)
    print(f"寫入 {out}：{len(data)} bytes，pixel clock {(HT * VT * MHZ // 1000) / 1e6:.2f} MHz，{HMM}×{VMM} mm")
