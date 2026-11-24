# 休眠（S4）計畫：FW13 移植 nullarc PR #20

狀態：**第 0 步 macOS 部分已完成（2026-11-24 21:56）**，還沒改任何東西。CachyOS 部分還沒做。

## 為什麼是休眠

- FW13 沒有 S3：CachyOS `/sys/power/mem_sleep` = `[s2idle]`；DSDT 的 `_S3` 只在 `CNSB == 0 && DAS3 == 1` 時才定義（HANDOFF「睡眠與硬體解碼：可行性評估」）。
- macOS x86 只會 S3，不支援 s2idle。能做的只有休眠：記憶體寫進磁碟 → 斷電 → 開機時還原。
- 喚醒＝冷開機（韌體 → systemd-boot → OpenCore → boot.efi 還原映像），要按電源鍵。休眠期間耗電接近關機。

## 來源

- nullarc PR #20（open，github.com/luuumi-dev/nullarc/pull/20）。base 是 `8aba872`（v0.4.0-alpha 之後 3 個 commit，
  都只動 README、Makefile、tests，**沒動 kext 原始碼**），所以 PhxBringup 的部分可以直接疊在我們的 v040 補丁上。
  commit：`0aedfd3`（GPU 恢復）、`63feca1`（PhxSleepPolicy + docs/SLEEP.md）、`1952bd3`、`8a2d943`／`6b930e0`（EC `_REG`）、
  `d424456`（phxwake：開機選單一次性跳過）。
- 作者在 MECHREVO WUJIE15XA（8745HS／780M、macOS 26.7）驗證：選單或闔上螢幕進入休眠，按電源鍵喚醒，kernel 恢復後約 2 秒桌面回來。
  **FW13 上沒有人驗證過。**

## PR #20 的各個部分，FW13 要怎麼處理

| 部分 | PR #20 | FW13 |
|---|---|---|
| ACPI `_S3` | DSDT 改名 `XS3_` → `_S3_`（沒有 `_S3`，macOS 回報「不支援睡眠」） | FW13 沒有 `XS3`，`_S3` 是條件式定義。改寫 SSDT：只在 Darwin 下、`\_S3` 不存在時建立（參考 660m-Metal `dist/acpi/SSDT-S3.dsl`）。**要先確認** macOS 下 `_S3` 到底在不在（第 0 步）。S3 本身永遠不會進入（PhxSleepPolicy 只回答「休眠」或「取消」）。 |
| PhxSleepPolicy.kext | 搶先註冊睡眠政策：開了休眠就回答 hibernate、否則 abort；把 `IOHibernateRTCVariables` 抄進 NVRAM；開機和每次喚醒跑 EC `_REG(3, 1)` | 從原始碼編（`src/sleeppolicy`，181 行）。EC `_REG`：FW13 的 EC 喚醒後會不會失去 ACPI 模式：**不知道**；先保留，boot-arg `-phxsleepnoecreg` 可以關掉開機時那次。 |
| OpenCore | `Misc → Boot → HibernateMode = Auto`、`HibernateSkipsPicker = true`；Kernel.Add 緊接 Lilu 之後放 PhxSleepPolicy | 一樣。照 HANDOFF 規則：備份 → 副本模擬 → diff → CachyOS 還原指令。 |
| pmset | `hibernatemode 25 standby 0 autopoweroff 0 powernap 0` | 目前 `disablesleep 1`（HANDOFF 表格）。最後一步才打開。 |
| boot-args | 文件寫：帶 `-v` 或 `debug=0x100` 時進入睡眠會卡住 | FW13 現在兩個都有，測試前要拿掉（`keepsyms=1` 可留）。 |
| PhxBringup | 睡眠時等 GPU 做完、擋住新的送出；喚醒後重新 adopt queue 才放行；丟掉舊的 VMID 綁定；hang check 暫停 | 做成 `phxbringup-v040-03-hibernate.patch` 疊在 01／02 上。**另外要處理我們自己的 VCN**：喚醒後 VCN 斷過電、VRAM（carve-out）內容沒了，`fw13VcnRingOk()` 會讀到重置值 → 回 NOT_UP，外掛退回軟體解碼。舊的 decode session（context 在 VRAM）要作廢：睡眠時把所有 session 標成失效，喚醒後同一個 handle 回 NO_SESSION。 |
| PhxAccel（PhxAMDFB + NMXAccel） | `debug.phxfb_wake=1` 打開 IOFramebuffer 的 paging gate；`debug.nvaccelfb=9` 補上沒收到的 display_mode_did_change、重新 enable accelerator | 我們的 `phxaccel-port` 不是 v0.4.0 原始碼（來自 nullarc 之後的 main，有 HiDPI、HDMI head 等改動），PR 的補丁直接套不上（`phxfb.cpp:410` 衝突）→ 手動移植 53 行。`resumeDisplay()` 用到 NMXAccel 物件內的固定位移（`+0x10c`、`+0xc78`），要確認我們這版一樣（`reportPipeGates` 已經用 `+0xc78`）。 |
| phxwaked + phxwake.sh | LaunchDaemon：每次喚醒後若 `GRBM_STATUS` = 0 就重跑 bring-up（`full.sh kiqsched`），再 phxfb_wake、nvaccelfb=9、時脈上限、clock gating | 照 FW13 的 phxboot.sh 補齊：時脈上限 `0x1B 800`＋`0x1E 800`、gpucg、sdma、`vcnctl up`。各自的關閉開關照舊（`gpucg-off`、`sdma-off`、`vcn-off`）。 |
| phxresume.py（開機選單一次性跳過） | 有 Boot Loader Interface 的選單（systemd-boot、Limine）：睡眠時寫 `LoaderEntryOneShot` = 這次 macOS 的 entry、`LoaderConfigTimeoutOneShot` = `menu-disabled` | FW13 是 systemd-boot → OpenCore，正好是 `bli` 模式。不做的話每次喚醒要在 systemd-boot 手動選 macOS（3 秒內），也能用，所以排在最後。一次性變數用過就被 systemd-boot 刪掉，**不影響 CachyOS 平常開機**。 |

## 另外發現：PhxAccel 裡的 Firebat EC 程式碼（跟休眠無關，但這次重編要一起處理）

`phxaccel-port/accel/nvrm-accel.cpp` 從本 repo 第一個 commit 起就帶著 nullarc main `1e0dbe9`（"add EC fan quiet mode … sysctl to PhxAccel"）
加的 Firebat U6C 專用程式碼，**沒有判斷機型**：

- `start()`（第 692 行）：`ml_io_map(0xFE0B0400, 0x100)`，寫 `+0x04 = 1`、`+0x18 = 0`、`+0x32 = 0x82`。
- `armFanWorker()` → `fanWorker()`（第 1352 行）：**每秒**寫 `+0x04`、`+0x17`、`+0x18`，依 `+0x70` 的值寫 `+0x74`、`+0x76`。
- sysctl `debug.firebat_fan_mode`：讀寫同一塊。

這些位移是 Firebat 的 EC 記憶體視窗。FW13 在實體位址 0xFE0B0400 有沒有東西、是什麼：**不知道**（要查 CachyOS 的 `/proc/iomem` 和 DSDT）。
目前裝的 PhxAccel（vblfix，sha `8938cdb4`）是這份原始碼編的，所以這段應該一直在跑；機器到目前穩定，風扇由 EC 控制也正常，
但對不明位址每秒寫入不應該留著。打算：重編 PhxAccel 時用 `#ifdef PHX_FIREBAT_EC` 包起來，FW13 不編進去。

## 步驟（每一步各自可以退回）

0. **只讀檢查**（`power/hib-check.sh`＋CachyOS 兩個指令）：macOS 下系統睡眠是否被當成「不支援」、記憶體／磁碟、
   systemd-boot BLI 變數 macOS 讀不讀得到、OpenCore 相關欄位、Firebat 程式碼有沒有跑；CachyOS：`dmesg` 的 ACPI 支援睡眠狀態列表、
   DSDT 的 `_S3` 區塊、0xFE0B0400 在 `/proc/iomem` 是什麼。
1. **PhxAccel 重編**：拿掉 Firebat EC、加上 PR #20 的 phxfb_wake／nvaccelfb=9。只換 kext，行為在沒睡眠時不變 → 先裝、用一陣子。
2. **PhxBringup build 138**：`phxbringup-v040-03-hibernate.patch`（PR #20 的 PhxBringup 部分＋VCN session 作廢）。沒睡眠時行為不變 → 先裝、用一陣子。
3. **PhxSleepPolicy.kext＋SSDT-S3＋OpenCore 欄位**：只放進 ESP，pmset 仍然 `disablesleep 1` → 不會真的睡。確認 `debug.phxsleep_installed = 1`、開機正常、CachyOS 正常。
4. **phxwaked**：裝 LaunchDaemon（只在喚醒時動作）。
5. **第一次休眠測試**：拿掉 `-v`、`debug=0x100`；`pmset hibernatemode 25 …`、`disablesleep 0`；手動 `pmset sleepnow`，按電源鍵、在 systemd-boot 選 macOS。
   失敗時的退路：開機選 CachyOS 一定能進（休眠映像只有 boot.efi 會讀）；macOS 那邊 `pmset -a disablesleep 1` 回到現狀。
6. 闔上螢幕觸發休眠；phxresume `bli` 跳過選單。

## 風險

- 睡眠中途失敗：PR #20 記錄 MT7922 Wi-Fi／藍牙可能要完全斷電（關機、拔電源、按住電源鍵 20 秒）才會恢復。FW13 的網卡型號在第 0 步確認。
- 休眠映像寫在 APFS（`/private/var/vm/sleepimage`，大小約等於記憶體），磁碟要夠。
- 喚醒後 GPU 沒回來：PR #20 的 kext 修改讓 WindowServer 等在 IOFramebuffer 的 gate、Metal client 等在 `gpuSubmit()`；phxwake.sh 失敗的話畫面不會回來，只能強制關機。
  強制關機後是一般冷開機，phxboot 照常跑。
- 喚醒後 phxboot 的 `MARK` 檔不會被碰到（phxwake.sh 不用它），所以失敗的喚醒不會讓下次開機把 GPU 關掉；要不要也加一個「喚醒失敗兩次就停用休眠」的保護，第 4 步再決定。

## 第 0 步結果（macOS，2026-11-24 21:56，`power/hib-check-1124-215605.txt` 在 Mac 上）

- **`IOSleepSupported = Yes`**、Supported Features 有 `Hibernation`、`DeepSleep`。PR #20 說沒有 `_S3` 時平台會回報不支援睡眠；
  這裡是支援 → ~~推論 macOS 下 `_S3` 存在~~ **更正（22:2x）**：BootFBSleep 掛了 `AppleACPIPlatformExpert::queryPlatformCanSleep`，hibernatemode 開著時直接回答 allow，所以 `IOSleepSupported = Yes` 可能是它造成的，**不能拿來判斷 `_S3`**。等 CachyOS 的 dmesg。
  （HANDOFF 記的「S3 醒不來」也符合：當時真的進了 S3。）
- `SleepDisabled = Yes`、AC `hibernatemode 0`、電池 `hibernatemode 3`。
- 記憶體 32768 MiB；Data 磁碟剩 108 GiB；`/private/var/vm` 是空的（還沒有 sleepimage）。
- NVRAM：macOS **讀得到** systemd-boot 的 Boot Loader Interface 變數：`LoaderInfo = systemd-boot 262.1-1-arch`、
  `LoaderEntrySelected = opencore.conf`、`LoaderEntryDefault = linux-cachyos-lts.conf` → phxresume `bli` 模式可用，entry 是 `opencore.conf`。
- OpenCore：`HibernateMode = NVRAM`（已經不是 None）、`HibernateSkipsPicker = false`、`ShowPicker = true`、Timeout 3、
  `DiscardHibernateMap = false`、`RequestBootVarRouting = true`（`bli` 模式不受影響）、`WriteFlash = true`。
  Kernel.Add：[0] Lilu、[37] PhxBringup、**[47] HibernationFixup（啟用）**、**[48] BootFBSleep（啟用）**，共 50 筆。
  PR #20：HibernationFixup 1.5.4 在 26.7 沒存到金鑰，有 PhxSleepPolicy 就不需要。兩個都抄同一個金鑰，第 3 步打算停用 HibernationFixup。
- **Firebat EC 程式碼確實在跑**：21:28:55 `Firebat EC init … FCMO=0xff`、`fan regulator armed`。讀回 0xff 通常表示那個位址沒有裝置回應
  （推論，未證實），所以寫入可能沒有作用；仍然要拿掉。
- 網卡：MT7922（0x14C3:0xE616，itlwm）→ PR #20 記錄的「睡眠失敗後要完全斷電」風險適用。
- boot-args 現在是 `… -smbtlefix acpi=0x200000`：`-v`、`debug=0x100` 都在（第 5 步前要拿掉）。

### repo 裡沒有紀錄、要先問使用者的

- **PhxAccel sha `d9c4d407`**：HANDOFF 記的是 vblfix `8938cdb4`。不知道 `d9c4d407` 是哪份原始碼編的。第 1 步要從原始碼重編 PhxAccel，
  base 不對會把現有的修改弄丟。
- **`BootFBSleep.kext`**（Kernel.Add [48]，ESP 上有 `.bak-1122f` 到 `.bak-1123a` 七個備份）：做什麼的、原始碼在哪，不知道。名字跟睡眠有關，
  可能跟 PhxSleepPolicy／phxfb_wake 重疊。
- **boot-arg `acpi=0x200000`**：HANDOFF 的 boot-args 沒有它。用途不知道。

### 追查（2026-11-24 22:0x）

- 裝著的 PhxAccel：`/Library/Extensions/PhxAccel.kext` 二進位時間 **11-23 03:44**（387008 bytes），比 vblfix（`backup/PhxAccel-vblfix.kext`，11-22 05:12）晚。
  → 11-23 03:44 有人換過 PhxAccel，安裝時把 vblfix 備份起來。repo（含 git 歷史、origin/main）沒有這次的紀錄。
- `BootFBSleep` 原始碼在 Mac 上的 `power/bootfbsleep/`，**沒進 repo**（不是 gitignore 擋的，是沒 commit）。
- 推論：11-22～11-23 有另一段工作只留在 Mac 上，沒推。要看 Mac 上的 `git status`。
- 2026-11-24 22:1x：`phxaccel-port` 現在的原始碼編出來是 `8938cdb4`（= vblfix 備份），**不是**裝著的 `d9c4d407` → 裝著的 PhxAccel 不是 repo 這份原始碼編的，來源還不知道。
- `power/bootfbsleep/build/BootFBSleep.kext`：`com.fw13.BootFBSleep` 1.7.0，`IOClass BootFBSleep`、`IOProviderClass IOResources`，有 `plugin_start.o` → Lilu 外掛。
  資料夾裡只有 .o 和 kext，**沒有原始碼**。
- Mac 上另有未 commit 的 `cppc/`（`cppc/src` 看起來是另一個 repo 的 clone，有 `build_kext.py`、`mesa_phoenix_*.py`；`cppc/build/PhxCPPC.kext`；紀錄 11-23 13:38）。
- `acpi=0x200000`：repo 的 md／sh 裡都沒有提到。
- 2026-11-24 22:2x：
  - **`d9c4d407` = vblfix ＋「HiDPI round 3」顯示縮放（DSCL）實驗**：多出 sysctl `phxfb_scaling`、`phxfb_scaletest`，boot-arg `-phxnoscale`，
    字串 "[port] HiDPI round 3: 1 = scaled modes through the display scaler…"、DCHUBP_CNTL 測試等。原始碼很可能在 Mac 上沒 commit 的 `display/dscl/`。
  - **BootFBSleep 就是先前一次休眠嘗試**（Lilu 外掛，1.7.0，ESP 上 7 個備份 1122f–1123a）。從字串看它掛了：
    `IOHibernateSystemSleep`、`IOHibernateSystemHasSlept`、`hibernate_setup`（記錄回傳值）；
    `IOPMrootDomain::updatePreventSystemSleepList`（"ignore system sleep preventer %s"、"remove existing preventer"）；
    `AppleACPIPlatformExpert::queryPlatformCanSleep`（"hibernatemode %u -> allow"）、`getSystemStateForSleepType`（"sleep type %u -> ACPI S%u"）。
    跟 PR #20 是同一件事的不同做法（PR #20：政策 handler＋NVRAM 金鑰；BootFBSleep：Lilu 掛函式）。結果如何、為什麼停下來：不知道，要問使用者。
  - `cppc/src`：沒有 remote 的 grafted clone，HEAD `77bac94 PhxCPPC 1.0.2`，跟 PhxAccel 無關。

### hib-history 結果（2026-11-25 03:51，`power/hib-history-1125-035140.txt` 在 Mac 上）

- **原始碼都找不到**：BootFBSleep 只有 `power/bootfbsleep/build/`（.o＋kext）和 `oc/kexts/BootFBSleep.kext`；`display/dscl/` 只有 Linux 的
  `dcn_3_1_4_offset.h`、`dcn_3_1_4_sh_mask.h`（11-23 02:13），沒有 PhxAccel 原始碼；scratch-workspaces 也沒有。→ `d9c4d407` 的原始碼視為遺失。
- **先前的休眠嘗試時間線**（ESP 的 config 備份）：`bak-1122b`（11-22 18:53）還是 `HibernateMode=None`、沒有 HibernationFixup／BootFBSleep。
  `bak-1122c`（20:33）開始 `HibernateMode=NVRAM`＋HibernationFixup；`bak-1122d`（20:45）加 BootFBSleep；`bak-1122e`（20:50）加 `acpi=0x200000`
  （`bak-1122f` 21:05 曾是 `acpi=0x1200000`，之後回到 0x200000）。BootFBSleep 1.0.0（11-22 20:33）→ 1.7.0（11-23 01:09）共 8 版。
  → **`acpi=0x200000`、HibernationFixup、`HibernateMode=NVRAM`、BootFBSleep 都是那次休眠嘗試加的。**`acpi=` 這個值的意義：不知道。
- pmset 紀錄和 kernel log 兩段都被 `head -40` 截在 11-22 中午以前，**看不到 11-22 20:30 之後**有沒有真的睡過。要再查一次。
- 診斷報告：11-22 之後只有 02:42、03:08 兩個 watchdog panic（螢幕關閉 VBL 問題，已修），沒有 Sleep Wake Failure。

### 先前休眠嘗試的 pmset 紀錄（11-22 20:30 → 11-23 02:00）

- GPU 接管當時是關的（Sleep notification 裡是 `IONDRVFramebuffer driver is slow`）。
- 20:54、21:13、21:18：`Entering Sleep state` → 下一筆就是新開機的 `ShutdownCause 5`，沒有 Wake。
- 21:32：睡 6 秒 `DarkWake from Normal Sleep`（XHC0），`hibmode=25`。21:38、21:54：`DarkWake from Invalid`、WakeTime 0.002 s（睡眠一開始就被取消）。
- **21:55 到 11-23 01:13 的 9 次都是同一個樣子**：`Entering Sleep state` → 約 1 分鐘後新開機，`ShutdownCause 5: Software initiated shutdown`，沒有任何 Wake／Hibernate 還原紀錄。
  最後一次 01:13（BootFBSleep 1.7.0 是 01:09 裝的），之後就停了。
- 推論（未證實）：休眠斷電本身是軟體發起的關機，所以「睡下去 → 寫映像 → 斷電」大概走完了；按電源鍵開機時沒有從映像還原，而是重新開機。
  這正是 PR #20 文件寫的狀況：PC 上沒有東西把 `IOHibernateRTCVariables` 存起來，OpenCore 回報 "RTC hibernation is 0, NVRAM hibernation is 0 / Not Found"、
  boot.efi `EB|H:FAIL`；HibernationFixup 1.5.4 在 26.7 沒存到。PhxSleepPolicy 的 `copyKey()` 就是補這一段。
  要證實：裝 PhxSleepPolicy 後在 OpenCore debug log（或 `nvram -p` 喚醒前）看金鑰有沒有存進去。
