# Licensing

This repository mixes code written for this project with code taken or adapted from other projects.
Each part keeps its own license. When a file carries its own license header, that header wins.

| Path | License | Copyright / source |
|---|---|---|
| Everything not listed below (`cstate/AMDCState.cpp`, `amdpmprobe/`, `vcn/`, `nullarc-port/bringup5.sh`, `tools/` except `collect-760m.c`, the shell scripts, `HANDOFF.md` and the other docs) | Apache-2.0, see [`LICENSE`](LICENSE) | © 2026 Kaoru0312 |
| `cstate/pmCPU.c`, `cstate/pmCPU.h` | Apple Public Source License 2.0 (APSL-2.0), <https://opensource.apple.com/apsl/> | © Apple Inc.; the original header is kept in each file |
| `phxaccel-port/` | PolyForm Noncommercial 1.0.0, see [`phxaccel-port/LICENSE.PolyForm-NC`](phxaccel-port/LICENSE.PolyForm-NC). **Noncommercial use only.** | Derived from NullMoth's macOS driver, via nullarc |
| `nullarc-pkg/` | Several licenses, see [`nullarc-pkg/LICENSE`](nullarc-pkg/LICENSE) and [`nullarc-pkg/THIRD_PARTY_NOTICES.md`](nullarc-pkg/THIRD_PARTY_NOTICES.md) | nullarc (<https://github.com/luuumi-dev/nullarc>) with local changes |
| `acpi/SSDT-S3.dsl` | GPL-2.0, as its source | Approach and code from 660m-Metal (rthh21/660m-Metal, GPL-2.0) `dist/acpi/SSDT-S3.dsl`, adapted for FW13 |
| `nullarc-kext/`, `nullarc-port/mesboot.c`, `nullarc-port/patches/`, `power/sleeppolicy/` (PhxSleepPolicy from nullarc PR #20, `d424456`, unchanged), the register sequence in `gpu/sdma.sh` and `gpu/sdma-test.sh` (from nullarc PR #24), `tools/collect-760m.c` | MIT ([`nullarc-pkg/LICENSES/MIT.txt`](nullarc-pkg/LICENSES/MIT.txt)), or at your option GPL-2.0-only ([`nullarc-pkg/LICENSES/GPL-2.0-only.txt`](nullarc-pkg/LICENSES/GPL-2.0-only.txt)), as nullarc | © 2026 luuumi-dev and the nullarc contributors, with local changes |
| `vcn/vcn_dec_vector.h`；`decodetest` in `vcn/vcnctl.c` follows the buffer layout and IB format of mechrevo-f7bsc `phxbringup-vcn.patch` | MIT, notice at the top of `vcn_dec_vector.h` | © Advanced Micro Devices, Inc. (libdrm `tests/amdgpu/decode_messages.h`), via mechrevo-f7bsc-hackintosh (MIT) |
| `vcn/vt/H264VCNDecoder.c` | MIT | Adapted from DrogaBox/ryzenstatus-utils `GPU/decode/av1/AV1VCNDecoder.c` (© 2026 DrogaBox, MIT); local changes |
| `vcn/h264/vcn_h264_msg.h`, `vcn/h264/vcn_h264_msg.c` | MIT | Structures and message layout from Mesa `src/amd/common/ac_vcn_dec.[ch]` and `src/gallium/drivers/radeonsi/mm/si_video_dec.c` (© Advanced Micro Devices, Inc. and Mesa contributors), with local code |
| `vcn/h264/testdata/vcn_quadrants.h264`, `fixture-*.h264` | MIT | From mechrevo-f7bsc-hackintosh `macos/nullarc/vcn/` (encoded with the macOS software H.264 encoder) |
| `vcn/h264/testdata/t*.h264`, `t*.framemd5`, `t*.order` | Apache-2.0, as this repository | Generated here with FFmpeg 6.1.1 / libx264 from the `testsrc2` pattern; the `.framemd5` and `.order` files are FFmpeg / ffprobe output |
| `nullarc-port/csb_gfx11.h`, `nullarc-port/mes_v11_api_def.h` | MIT-style license, notice at the top of each file | © Advanced Micro Devices, Inc. (from Linux `amdgpu`) |
| `gpu/gpucg-test.sh`、`gpu/gpucg.sh` 的暫存器寫入序列 | MIT，同 mechrevo-f7bsc `macos/thermal/gpucg.sh` | © WUJIE15XA-Hackintosh contributors（QiRanChenk/MECHREVO-WUJIE15XA-8745HS-Hackintosh）；其餘部分同本 repo |
| `i2c/patches/`, `i2c/VoodooI2CHID-Info.plist.orig` | GPL-3.0, as VoodooI2C | Patches against / files from VoodooI2C (<https://github.com/VoodooI2C/VoodooI2C>) |

## PolyForm Noncommercial: Required Notice

Anyone who receives `phxaccel-port/` (or the PolyForm parts of `nullarc-pkg/`) must also receive the license terms and
this line:

```
Required Notice: Copyright (c) 2026 NullMoth Systems (https://nullmothsystems.com)
```

## Not in this repository

The OpenCore `config.plist` with SMBIOS serials, third-party SDKs and source trees, GPU/VCN firmware and compiled
binaries are kept out on purpose (see [`.gitignore`](.gitignore)). Nothing from Apple is redistributed apart from the two
APSL source files listed above.
