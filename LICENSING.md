# Licensing

This repository mixes code written for this project with code taken or adapted from other projects.
Each part keeps its own license. When a file carries its own license header, that header wins.

| Path | License | Copyright / source |
|---|---|---|
| Everything not listed below (`cstate/AMDCState.cpp`, `amdpmprobe/`, `vcn/`, `nullarc-port/bringup5.sh`, `tools/` except `collect-760m.c`, the shell scripts, `HANDOFF.md` and the other docs) | Apache-2.0, see [`LICENSE`](LICENSE) | © 2026 Kaoru0312 |
| `cstate/pmCPU.c`, `cstate/pmCPU.h` | Apple Public Source License 2.0 (APSL-2.0), <https://opensource.apple.com/apsl/> | © Apple Inc.; the original header is kept in each file |
| `phxaccel-port/` | PolyForm Noncommercial 1.0.0, see [`phxaccel-port/LICENSE.PolyForm-NC`](phxaccel-port/LICENSE.PolyForm-NC). **Noncommercial use only.** | Derived from NullMoth's macOS driver, via nullarc |
| `nullarc-pkg/` | Several licenses, see [`nullarc-pkg/LICENSE`](nullarc-pkg/LICENSE) and [`nullarc-pkg/THIRD_PARTY_NOTICES.md`](nullarc-pkg/THIRD_PARTY_NOTICES.md) | nullarc (<https://github.com/luuumi-dev/nullarc>) with local changes |
| `nullarc-kext/`, `nullarc-port/mesboot.c`, `nullarc-port/patches/`, the register sequence in `gpu/sdma.sh` and `gpu/sdma-test.sh` (from nullarc PR #24), `tools/collect-760m.c` | MIT ([`nullarc-pkg/LICENSES/MIT.txt`](nullarc-pkg/LICENSES/MIT.txt)), or at your option GPL-2.0-only ([`nullarc-pkg/LICENSES/GPL-2.0-only.txt`](nullarc-pkg/LICENSES/GPL-2.0-only.txt)), as nullarc | © 2026 luuumi-dev and the nullarc contributors, with local changes |
| `vcn/vcn_dec_vector.h`；`decodetest` in `vcn/vcnctl.c` follows the buffer layout and IB format of mechrevo-f7bsc `phxbringup-vcn.patch` | MIT, notice at the top of `vcn_dec_vector.h` | © Advanced Micro Devices, Inc. (libdrm `tests/amdgpu/decode_messages.h`), via mechrevo-f7bsc-hackintosh (MIT) |
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
