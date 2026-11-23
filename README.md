# fw13-hackintosh

Framework 13 AMD（Ryzen 5 7640U／Radeon 760M）的 macOS Tahoe 和 CachyOS 雙系統工作記錄。

- **從這裡開始讀：[HANDOFF.md](HANDOFF.md)**：目前狀態、設定、救援指令、量測結果和下一步。
- 各資料夾放的是安裝／還原腳本和自製 kext 原始碼。
- 這個 repo 刻意**不放**以下東西：含 SMBIOS 序號的 config.plist、第三方 SDK／原始碼、二進位檔，詳見 `.gitignore`。
- 授權：自己寫的部分是 Apache-2.0，部分資料夾例外（含僅限非商業使用的 `phxaccel-port/`），詳見 [LICENSING.md](LICENSING.md)。

## English summary

Working notes, scripts and kext sources for running macOS Tahoe 26.6 on a Framework Laptop 13 (AMD Ryzen 5 7640U,
Radeon 760M), dual-booted with CachyOS. GPU acceleration comes from a port of
[nullarc](https://github.com/luuumi-dev/nullarc) to the 760M (PCI `1002:15bf`). The detailed log is in
[HANDOFF.md](HANDOFF.md) (Traditional Chinese).

This is a personal work log, not an installer. Paths in the scripts assume `/Users/kaoru/fw13-hackintosh`; adjust them
before use. No `config.plist` is included: build your own with your own SMBIOS values
(`nullarc-pkg/EFI/OC/Sample.plist` holds placeholders only).

### Hardware

| Part | Detail |
|---|---|
| Model | Framework Laptop 13 (AMD Ryzen 7040 series), 32 GB RAM |
| CPU | Ryzen 5 7640U (Phoenix, Zen 4) |
| iGPU | Radeon 760M, PCI `1002:15bf`, subsystem `f111:0006`; BIOS iGPU memory set to 4 GB |
| Display | 2256×1504, 13.5" 3:2 |
| Wi-Fi / BT | MediaTek RZ616 |
| Bootloader | systemd-boot → OpenCore 1.0.8 → macOS; CachyOS boots directly from systemd-boot |

### Status (as of 2026-11-21, from HANDOFF.md §0b)

Only items actually tested are marked as working.

| Feature | Status |
|---|---|
| Boot (macOS + CachyOS dual boot) | ✅ |
| GPU: Metal, WindowServer compositing, apps on GPU | ✅ via nullarc port, 760M topology fixed |
| Native resolution 2256×1504 | ✅ |
| HiDPI / scaled resolutions | ❌ PhxFB only accepts the native mode |
| Keyboard, brightness and volume keys | ✅ |
| Trackpad (multi-touch gestures) | ⚠️ occasionally dead after boot; a VoodooI2CHID patch is under test |
| Audio: speakers, internal mic | ✅ VoodooHDA |
| Headphone jack | ❓ not tested |
| Wi-Fi | ✅ AirportMtkWlan |
| Bluetooth (classic + BLE) | ✅ BLE needs `-smbtlefix` |
| USB receiver | ✅ |
| Battery status | ✅ SMCBatteryManager + ECEnabler |
| Hardware video decode | ❌ software decode only |
| Sleep | ❌ disabled, S3 does not wake |
| Idle package power | ~11 W with GPU takeover (CachyOS ~5.5 W) |
| USB storage, external display / HDMI, webcam, fingerprint, AirDrop / Handoff, Bluetooth audio | ❓ not tested |
