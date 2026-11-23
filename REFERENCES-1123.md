# 參考專案盤點（2026-11-23）

使用者指定的 5 個 repo，加上其中一個（mechrevo-f7bsc）引用的 nullarc 上游 PR，逐一對照 HANDOFF.md 的待辦與未解問題。
每一項都附出處（repo、路徑、commit）。「FW13 上沒驗證」的地方都有標出來。

查看時各 repo 的 HEAD：

| repo | HEAD | 硬體 |
|---|---|---|
| [sfyyy/mechrevo-f7bsc-hackintosh](https://github.com/sfyyy/mechrevo-f7bsc-hackintosh) | `ea8ab6c`（2026-11-23） | 7840H／780M（Phoenix，PCI 15bf），nullarc 0.4.0，HDMI 迷你主機 |
| [luuumi-dev/nullarc](https://github.com/luuumi-dev/nullarc) PR #14、#20、#24、#25 | main `3497d87` | 上游，多台 Phoenix／Hawk Point |
| [DrogaBox/ryzenstatus-utils](https://github.com/DrogaBox/ryzenstatus-utils) | `6c76dc9`（2026-11-23） | RX 6800 XT 獨顯；CPU kext 支援 Phoenix |
| [pcdgck/gem12-tahoe-hackintosh](https://github.com/pcdgck/gem12-tahoe-hackintosh) | `8372b63`（2026-11-24） | 8845HS／780M（1002:1900），nullarc，HDMI 迷你主機 |
| [rthh21/660m-Metal](https://github.com/rthh21/660m-Metal) | `d5937e5`（2026-11-23） | 6600HS／660M（Rembrandt，RDNA2），用 Apple 自己的 Navi 23 驅動 |
| [OscarrWu/780m-hackintosh](https://github.com/OscarrWu/780m-hackintosh) | `965d83f`（2026-11-22） | 780M，自己寫的驅動，路線圖階段 4 還沒完成 |

## 總結（依對 FW13 的價值排序）

| # | 項目 | 對應 HANDOFF | 來源 | FW13 狀態 |
|---|---|---|---|---|
| 1 | **GPU 閒置功耗：CP 一直 busy**（doorbell range + MES oversubscription timer） | 待辦 4（GPU 接管約 4 W）、GFXOFF 實驗沒效果 | nullarc PR #14 | 已確認 FW13 的 `mesboot.c` 有同樣的缺漏；補丁已備好，**還沒編譯、還沒上機** |
| 2 | GFX 時鐘閘控（MGCG/CGCG）→ SDMA 解除 halt → GFXOFF | 同上 | nullarc PR #14 build 37、#24、#25；mechrevo `macos/thermal/gpucg.sh` | 要在第 1 項之後做 |
| 3 | **休眠（S4）含 GPU 恢復** | 睡眠 ❌ | nullarc PR #20（`docs/SLEEP.md`）；660m-Metal `SSDT-S3.dsl` | 沒驗證 |
| 4 | H.264 硬解（Phoenix VCN 4.0.2） | 硬解 ❌、`vcn/PHASE3.md` | mechrevo `patches/phxbringup-vcn.patch`、`macos/nullarc/vcn/` | 沒驗證；PHASE3 的一個結論要更正 |
| 5 | NVMTL 外掛的修正（Vision/OCR 閃退、WindowServer 效能、Ghostty） | all_apps 之後的穩定性 | mechrevo `macos/nullarc/patches/nvmtl-*.patch` | 沒驗證 FW13 有沒有這些症狀 |
| 6 | PhxAccel 顯示修正（67 ms 卡頓、撕裂、殘影） | 畫面順暢度 | mechrevo `patches/phxaccel-*.patch` | 沒驗證 |
| 7 | PhxBringup 每個行程的 GPU 頁表上限（2 GiB） | 截圖／錄影時 WindowServer 當掉 | mechrevo `patches/phxbringup-ptfix.patch` | FW13 有沒有這個症狀：不知道 |
| 8 | CPU：CPPC／EPP | §9b 階段 1 | ryzenstatus-utils `SMCAMDProcessor_Source`（3.42.0） | FW13 目前用 0.7.2，沒試過 |
| — | HiDPI | 待辦 3 | **5 個 repo 都沒有解法**（mechrevo、gem12 都寫「无 HiDPI」） | — |

---

## 1. GPU 閒置功耗：CP 一直 busy（最值得先做）

**來源**：mechrevo `docs/known-issues.md`「核显空闲时仍"忙碌"（nullarc#14）」；上游
[luuumi-dev/nullarc#14](https://github.com/luuumi-dev/nullarc/pull/14)（open，沒合併）的 commit：

- `ae5a464` mesboot：建立第一個佇列**之前**寫 `CP_MEC_DOORBELL_RANGE_LOWER/UPPER = 0 / 0x450`、`CP_MAX_CONTEXT = 7`、`CP_DEVICE_ID = 1`。
  nullarc 0.4.0 沒寫，重設值 0x110..0xffc 涵蓋 gfx ring 的 doorbell 0x458。gfx 佇列建立後 CP 就一直 busy
  （`GRBM_STATUS = 0xa800302c`，Linux 閒置時是 `0x0000302c`）。commit 訊息寫明：佇列建立後再寫**沒有用**。
- `61a2226` mesboot：`SET_HW_RESOURCES.oversubscription_timer` 從 50 改成 0（Linux `mes_v11_0_set_hw_resources` 在實機上不開）。
- `ed747f7` mesboot：MES 遮罩改成 Linux 的值（vmid 0x0000ff00、gfx_hqd 0x00000002）。

**上游的結果**（`8cec986` 的 BUGS.md B-34，ACEMAGIC RX16、Ryzen 7 255）：GRBM 回到 `0x0000302c`、GFX 負載 0 %、GFXCLK 800 MHz，
閒置封裝功耗從 22–36 W 降到 **5.2 W**。

**跟 FW13 的關係**：

- FW13 的 `nullarc-port/mesboot.c` 已經對照過：第 622 行是 `oversubscription_timer = 50`，整個檔案沒有寫 `0x1dfc`／`0x1dfd`
  （`CP_MEC_DOORBELL_RANGE`）→ 跟上游修正前一樣。
- HANDOFF 記錄 GFXCLK 曾卡在 2600 MHz、現在靠 phxboot 送 SMU 指令壓在 800 MHz；GPU 接管還是多吃約 4 W；送 GFXOFF(0x19) 沒效果。
  這三個現象都符合「CP 一直 busy」（推論，還沒在 FW13 量 `GRBM_STATUS`）。
- FW13 的 GC 版本跟 780M 一樣是 11.0.1（`gpu-topology/fw13-ip.txt` 第 1 行 `discovery=0x000b0001`），暫存器位址可以直接用。

**已備好的補丁**：`nullarc-port/patches/mesboot-idle-pr14.patch`（套在 FW13 的 `mesboot.c` 上，三項都可以用環境變數關掉：
`MESBOOT_LEGACY_INIT=1`、`MESBOOT_OVERSUB=50`、`MESBOOT_VMIDMASK=0xffffff00 MESBOOT_GFXMASK=0xfffffffe`）。
**`nullarc-port/mesboot.c` 本身沒有改**，所以 repo 裡的原始碼仍然對應目前安裝的版本。只在 Linux 上用假的 IOKit 標頭做過語法檢查，
**還沒在 Mac 上編譯，也還沒上機**。

**建議的驗證順序**（每一步都可以還原）：

1. 唯讀確認：GPU 接管開著、閒置時跑 `sudo /Users/Shared/gpu/phxctl/phxctl regs 0x2004`。讀到 `0xa800302c` 就是同一個問題；
   讀到 `0x0000302c` 表示 FW13 沒有這個問題，後面不用做。（FW13 的 `nullarc-port/bringup5.sh` 第 52 行已經用
   `phxctl regs … 0x2004` 讀過同一個暫存器，所以這個子指令存在；repo 裡的 log 沒有留下讀值。）
2. 套補丁、編 mesboot、換掉 `/Users/Shared/gpu/phxctl/mesboot`（先備份），重開機。看 `GRBM_STATUS` 和閒置封裝功耗。
3. 出問題：換回備份的 mesboot；開不了機的處理方式跟現在一樣（phxboot-off）。

## 2. 時鐘閘控 → GFXOFF（第 1 項之後）

- nullarc PR #14 `9f37791`：PhxBringup build 37 預設開 GFX 時鐘閘控（MGCG + CGCG/CGLS）。
- mechrevo `macos/thermal/gpucg.sh`：同樣的暫存器序列（照 Linux `gfx_v11_0_update_gfx_clock_gating()`），用 phxctl 從使用者空間寫，
  `status|mgcg|cgcg|all|off`，**不用重編 kext**。mechrevo 自己的說明：在 CP busy 沒修好的情況下只能「緩解」。
- nullarc PR #24（open）`37a7b16`／`0a3bd8a`：mesboot 讓 SDMA0 離開 halt（`MESBOOT_SDMA=1`），RLC 才會閘控 GFX 時鐘。
- nullarc PR #25（**closed**，沒合併）`c9b0abc`：PhxBringup 自己管 Allow/DisallowGfxOff，閒置時設定 `RLC_PG_CNTL`／`RLC_PG_DELAY_3`
  再送 AllowGfxOff。作者（8745HS）量到閒置封裝 6.0 → 4.9 W。commit 訊息寫明：沒有讓 SDMA 離開 halt，RLC 什麼都不會閘控。
  → 這可以解釋 FW13 的 GFXOFF 實驗為什麼沒效果（推論）。PR 已關閉，原因不知道。

## 3. 休眠（S4）

**來源**：nullarc PR #20（open）`docs/SLEEP.md` 與 `0aedfd3`、`63feca1`、`8a2d943`、`6b930e0`、`d424456`。
作者在 MECHREVO WUJIE15XA（8745HS、macOS 26.7）驗證：選單或闔上螢幕進入休眠，按電源鍵喚醒，kernel 恢復後約 2 秒桌面和所有視窗回來。

跟 FW13 對得上的地方：

- 文件寫明 Phoenix/Hawk Point 筆電只有 Modern Standby、強制 S3 醒不來，跟 HANDOFF「睡眠與硬體解碼：可行性評估」的結論一致。
- `PhxSleepPolicy.kext`：讓 X86PlatformPlugin 的睡眠政策回答「休眠」而不是 S3，並把休眠金鑰（`IOHibernateRTCVariables`）寫進 NVRAM
  （文件寫 HibernationFixup 1.5.4 在 26.7 上沒存到金鑰）。
- GPU 恢復：喚醒後 `phxwaked` 重跑 bring-up（約 3 秒），PhxBringup／PhxAMDFB／NMXAccel 在睡眠期間擋住送出的工作。
- **`tools/phxwake/phxresume.py` 支援 systemd-boot**（寫 `LoaderEntryOneShot`），FW13 就是 systemd-boot → OpenCore。
- EC：喚醒後再跑一次 EC 的 `_REG(3, 1)`，否則闔上螢幕、亮度鍵失效。FW13 的 EC 會不會這樣：不知道。

FW13 要注意的差異：

- FW13 的 DSDT 沒有 `XS3`，`_S3` 是有條件才定義（`CNSB == 0 && DAS3 == 1`，HANDOFF 已記錄）。PR #20 用的 `XS3_ → _S3_` 改名**不適用**。
  660m-Metal 的 `dist/acpi/SSDT-S3.dsl` 處理的正好是同一個條件式：只在 Darwin 下、`_S3` 不存在時才建立
  （`If (LNot (CondRefOf (\_S3)))`），另外用 `\_SB.RMS3` 的 `_STA` 把 `DAS3`、`CNSB` 的值露出到 ioreg。可以照這個寫 FW13 版本。
  拿到 `DAS3` 的值也能確認韌體的 S3 是不是整個關掉。
- 文件寫「不要帶 `-v` 或 `debug=0x100` 測試，會在進入睡眠時卡住」。FW13 目前的 boot-args 兩個都有。
- 需要從原始碼重編 PhxBringup／PhxAccel（FW13 的 PhxBringup 目前是 release 二進位改 10 bytes）。

## 4. H.264 硬解（VCN 4.0.2）

- mechrevo `macos/nullarc/patches/phxbringup-vcn.patch`（5065 行，PhxBringup build 64/65/75）：Phoenix VCN 4.0.2 的 H.264 編碼與解碼。
  `macos/nullarc/vcn/BENCHMARKS.md`（build 75，2026-11-23）：同一段 H.264，硬解時 1080p30 單核 CPU 31.8 % → 18.8 %，0 錯誤幀；
  後續 IDR 延遲約 32 ms（可能每個關鍵幀掉一幀）。
- FW13 的 VCN 也是 4.0.2（`gpu-topology/fw13-ip.txt` type 6–8 `discovery=0x00040002`）。FW13 的 `vcn/` 階段 1–2 做到的
  （VCN 啟動、unified queue、MMHUB page table）跟這個補丁是同一段工作，可以拿來對照。
- 這個解碼器能不能讓 Safari／系統全域使用：**不知道**。mechrevo 的 `vcn/README.md` 寫明 H.264 **編碼器**裝在
  `/Library/Video/Plug-Ins` 時會被 CoreMedia 的簽章檢查過濾，只能在應用程式自己的行程裡註冊；解碼的部分沒找到同樣明確的說明。

**`vcn/PHASE3.md` 要更正的地方**：PHASE3 把路線 D（第三方 VT 解碼外掛）判為「不可行」。ryzenstatus-utils 的
`GPU/docs/how-it-works.md`「How VideoToolbox finds them」寫：VideoToolbox 讀 **`/System/Library/Video/Plug-Ins`** 裡的解碼器
**不檢查簽章**，只有 `/Library/Video/Plug-Ins` 要求 Apple 簽章；他們的 AV1／VP9 解碼器（`CMClassImplementations`、
`VTIsHardwareAccelerated`）讓 Safari 和 Chrome 在 `VTDecoderXPCService`／`com.apple.WebKit.GPU` 裡載入。
代價是要 `csrutil authenticated-root disable`、改系統磁碟區。這是他們在 RX 6800 XT、Tahoe 26.7.3 的結果，**FW13（26.6）沒驗證**。
他們的解碼器底下走 Apple 的 `AMDRadeonVADriver2`，FW13 沒有這層，所以只有「註冊方式」能參考，解碼本體要接 FW13 自己的 VCN 路徑。
另外：AV1／VP9 系統本來就沒有硬體解碼器，蓋不蓋得掉內建 H.264 的問題不存在，YouTube 用的正是 VP9／AV1。

## 5. NVMTL 外掛（Metal 驅動）的修正

都在 mechrevo `macos/nullarc/patches/`，說明在 `docs/known-issues.md`。都要用 Vulkan-Headers 重編 NVMTLDriver。FW13 開了 all_apps，
以下問題理論上都會遇到，但 **FW13 上都沒驗證過**：

- `nvmtl-nn-hide.patch`：任何在自己行程裡呼叫 Vision 文字／條碼辨識（或走 Espresso 的 Core ML）的 App 會 `abort`
  （例：Shottr、QQ）。補丁讓推理堆疊看不到 GPU、改用 CPU。
- `nvmtl-surface-key.patch` + `nvmtl-perf2-surface-in.patch` + `nvmtl-fetch-mask.patch`：WindowServer 開 Chrome 時約 70 % → 38 %、
  忙碌樣本少約 45 %。
- `nvmtl-env-no-mutation.patch`：外掛修改宿主行程環境變數，讓 Ghostty 1.4.0 閃退。
- 注意事項（同一份文件）：不要用上游的 `plugdeploy.sh`，會覆蓋 `nvrm610.conf`；開機後不要手動重跑 `phxboot.sh`。

## 6. PhxAccel 顯示修正

- `phxaccel-vbl-timing.patch`：CVDisplayLink 每隔幾秒出現 33／50／67 ms 的間隔。根因是 PhxAMDFB 的 `getTimingInfoForDisplayMode`
  回傳空的時序，IOFramebuffer 沒進「時序模式」，vblDelta 隨軟體 tick 抖動。FW13 的 `phxaccel-port/accel/phxfb.cpp` 來源相同，
  推測有同樣問題（沒驗證）。FW13 已經有自己的 VBL 修正（螢幕關閉時不停 tick），兩個補丁改的是不同地方，要手動合併。
- `phxaccel-dbuf.patch`：雙緩衝，修拖動視窗時的撕裂（`debug.phxfb_dbuf`）。
- `phxaccel-surface-marks.patch` + `nvmtl-surface-marks.patch`：動畫殘影（上游 B-58）的根因修正。mechrevo 自己寫「尚未安装/重启验证」。

## 7. PhxBringup 頁表上限（ptfix）

mechrevo `patches/phxbringup-ptfix.patch`（build 35）與 gem12 README 第 2、4 點：每個行程的 GPU 頁表 64 塊 ≈ 2 GiB，
WindowServer 長時間執行加上截圖緩衝就撞到上限 → SkyLight `abort`（截圖、錄影、螢幕共享時黑屏回登入畫面）。
gem12 強調 PhxAccel 的 VRAM 池要跟 PhxBringup 的 `kHiTotal` 對齊，且數值是照 8 GB UMA 設的；FW13 是 4 GB，數值要重算。
gem12 套了 ptfix 之後截圖**仍然失敗**（`docs/04-已知问题.md` 1.2）。

## 8. CPU：CPPC／EPP

ryzenstatus-utils `SMCAMDProcessor_Source/README.md`：AMDRyzenCPUPowerManagement **3.42.0** 列出支援 family 19h model 74h
（FW13 的 7640U，AMDPMProbe 讀到的就是 Family 0x19 Model 0x74），功能有 CPPC MSR 寫 EPP、`-amdcppcactive`（開機就進 CPPC
自主模式）、自己的 CC6 閒置迴圈（讀 MSR `0xC0010073` 取得 C-state I/O 位址）。FW13 目前用的是 0.7.2（HANDOFF「溫度／頻率監看」）。
§9b 階段 1 想做的「啟用 CPPC、設 EPP」這版已經做了。
限制：FW13 已量過「核心 C-state 不是瓶頸」（AMDCState 重測），所以 CC6 這部分預期幫助不大；EPP 的效果沒有量過。
要 OpenCore 的 AMD Vanilla 補丁與 `ProvideCurrentCpuInfo`（該 README「OpenCore requirements」）。repo 裡的
`nullarc-pkg/EFI/OC/Sample.plist` 有 `ProvideCurrentCpuInfo = true`，但 FW13 實際使用的 config.plist 不在 repo 裡，要在 ESP 上查。

## 其他（價值低或不適用）

- **gem12**：大部分跟 mechrevo 重複（ptfix、vbl-timing、dbuf）。`scripts/vtdec-guard.sh`（動態桌布讓 VTDecoderXPCService 吃滿 CPU 時的看門狗）
  FW13 已經知道這個問題、也決定不用動態桌布。音效是 AMD ACP、跟 FW13 的 AZAL＋ALC295 不同，不適用。
- **660m-Metal**：用 Apple 的 Navi 23 驅動跑 RDNA2，架構跟 nullarc 完全不同，GPU 部分不能移植。可參考的只有 `SSDT-S3.dsl`（第 3 項）和
  `SSDT-XHCWAKE.dsl`（S3 時 XHC 的 PME 一直把機器叫醒的處理方式，FW13 若走 S3 才用得到）。
- **780m-hackintosh**：自己寫的 GPU 驅動，顯示與加速（階段 4）還沒完成，目前不能拿來用。`src/dcn314/` 有從 Linux 產生的 DCN 3.1.4 暫存器表，
  如果之後要自己做 HiDPI 需要的 DCN 縮放器，可以當對照，但 FW13 的 `nullarc-kext/amd/phx_dcn314_*.h` 已經有類似內容。
- **XhciNudge**（mechrevo 用的 USB 中斷補丁）：FW13 的 `fchxhcimode=1` 已經是「有事件才轉送」，mechrevo 的待辦正是要做 FW13 已經做到的事，不用參考。
- **HiDPI**：沒有任何一個 repo 解決。
