# 休眠（S4）計畫：FW13 移植 nullarc PR #20

狀態：**走路線 C（2026-11-25）**：先不動 PhxAccel（保留 d9c4d407 的縮放），做 PhxBringup 138、PhxSleepPolicy、OpenCore；先測「開機能不能從休眠映像還原」（可以在 GPU 接管關閉時測）。
目前：**第 2、3 步完成**（2026-11-25 04:12）；**第 5 步第一次測試**的開關 `power/hib-test.sh` 寫好，還沒執行。

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

## 第 2 步：PhxBringup build 138（`phxbringup-v040-03-hibernate.patch`）

- 內容：PR #20 `0aedfd3` 的 PhxBringup 部分原封不動（`suspended`／`retiredAtSleep`／`resumeEvent`；setPowerState(0) 等 GPU 做完再擋送出；
  adoptQueue 重新 adopt 時丟掉舊 VMID 綁定、gfx queue adopt 完才放行；`gpuRetired()` 睡眠中回傳凍結值；`gpuSubmit()` 睡眠中等待；hangCheck 暫停），
  再加 FW13 的一段：setPowerState(0) 時在 `fw13VcnLock` 下把開著的 VCN session 作廢（`fw13VcnOwner = nullptr`、丟掉 alias 映射）。
- PR #20 的 diff 疊在 01／02 上：7 個 hunk 都套得上（第 1 個 fuzz 2，只是宣告位置），結果跟 PR 一致。
- 這裡（Linux）用 MacKernelSDK `-fsyntax-only` 編過：0 error、0 warning。真正的編譯和連結要在 Mac 上跑 `gpu/phxbringup-fw13-build.sh`。
- 沒有睡眠時的行為：`suspended` 永遠是 false；開機時 adopt 前沒有任何 VMID 綁定，丟綁定那段什麼都不做 → 跟 137 一樣。
- **已裝（2026-11-25 04:0x）**：第一次開機卡在 verbose 畫面（最後幾行是 itlwm、USB 連接埠、NVMe；PhxBringup 已 `service up`、印了開機時的 `wake: nothing held`），
  強制關機再開就正常。是不是 138 造成的：不知道（這個階段 138 跟 137 執行的程式一樣）。再發生要記下來。
  04:07 確認：`phx-build = 138`、`PhxAMDFB on the panel: 1`、Metal for every app、vcn up rc 0、phxboot done。

## 第 3 步：PhxSleepPolicy＋OpenCore（`power/hib-oc-install.sh`）

- `power/sleeppolicy/`：PR #20 `d424456` 的 `src/sleeppolicy` 原封不動（MIT／GPL-2.0-only）。這裡 `-fsyntax-only` 0 error。
- config.plist：Kernel.Add 最後面加 PhxSleepPolicy（不插在 Lilu 後面，因為 repo 的腳本用固定編號）；停用 [47] HibernationFixup、[48] BootFBSleep；
  boot-args 拿掉 `acpi=0x200000`；`HibernateSkipsPicker = true`。`-v`、`debug=0x100` 這步先不動。
- 睡眠仍關著（`SleepDisabled = 1`），裝完不會真的睡。開機後看：
  - `debug.phxsleep_installed`：1 = 搶到睡眠政策；-1 = 別人先註冊（那就要把它移到 Lilu 後面）。
  - `IOSleepSupported`：BootFBSleep 停用後如果變成沒有／No → macOS 下真的沒有 `_S3`，要加 SSDT-S3；還是 Yes → `_S3` 存在，不用 SSDT。
    這樣就能回答 `_S3` 的問題，不用到 CachyOS 查。
- **第 3 步結果（2026-11-25 04:12 開機）**：`debug.phxsleep_installed = 1`（放在 Kernel.Add 最後也搶得到）、`phxsleep_ecreg = 1`、`_last = 0`；
  `IOSleepSupported = Yes`（BootFBSleep 已停用）→ 推論 macOS 下 `_S3` 存在，**不需要 SSDT-S3**；boot-args 沒有 `acpi=`；載入的只有 PhxSleepPolicy。

## 第 5 步：第一次休眠測試（只看「能不能從映像還原」）

- 為什麼不在 GPU 關閉時測：PR #20 寫「GPU 關閉（phxboot-off）時開機 framebuffer `.Display_boot` 會擋住系統睡眠」，pmset 紀錄裡也看過
  `Kernel System sleep preventers: .Display_boot`（先前 BootFBSleep 就是在掛 `updatePreventSystemSleepList` 忽略它）。所以在 GPU 開著時測。
- 預期：PhxAccel 還沒有 phxfb_wake／nvaccelfb=9，也還沒有 phxwaked → 還原成功的話畫面大概黑的（WindowServer 卡在 IOFramebuffer 的 gate，
  PR #20 說最後被 watchdog panic）。判斷有沒有還原，看強制重開後的紀錄：pmset log 有沒有 Wake／HibernateStats、上一次開機的 kernel log
  有沒有 `PhxBringup: wake: waiting for the bring-up…`、`PhxSleepPolicy` 有沒有寫金鑰（`phx-sleep-note` NVRAM）。
- 喚醒時 systemd-boot 預設是 CachyOS（`LoaderEntryDefault = linux-cachyos-lts.conf`），**要在 3 秒內手動選 macOS（OpenCore）**；選錯了開進 CachyOS 也沒關係，
  映像只有 boot.efi 會讀，下次選 macOS 會再試著還原（或丟掉映像正常開機）。
- 風險：MT7922 在睡眠中途失敗後可能要完全斷電（關機、拔電、按住電源 20 秒）才恢復。

### 第一次測試（2026-11-25 04:2x）：被 `kPMPCIUnsupported` 擋下，**更正：macOS 下沒有 `_S3`**

- `debug.phxsleep_calls = 1`、`last_type = 4`（休眠）、`last_mode = 25`，`phxsleep_key_writes = 0`；`/var/vm/sleepimage` 16 GiB 建好了；uptime 沒斷（沒有斷電）。
- kernel：04:26:50 `sleep reason Idle Sleep` → `System sleep prevented by kPMCPUAssertion`；04:27:05 DarkWake 中再試 → **`System sleep prevented by kPMPCIUnsupported`**。
  PR #20 docs/SLEEP.md：沒有 `_S3` 時「every sleep request ends in `System sleep prevented by kPMPCIUnsupported`」。
  → 前面用 `IOSleepSupported = Yes` 推論 `_S3` 存在**是錯的**；先前 BootFBSleep 掛 `AppleACPIPlatformExpert::queryPlatformCanSleep` 就是在繞這一關。
- 另外：電池的 pmset `sleep 1`（閒置 1 分鐘就睡），`hib-test.sh on` 原本只照 AC 的 `sleep 0` 說「只有手動才會睡」，是錯的；
  已改成 on 時 `pmset -a sleep 0`、off 時還原。這次的「變黑、半亮」是閒置睡眠一直被觸發又被擋。
- 下一步：SSDT-S3（只在 Darwin、`\_S3` 不存在時定義），數值照 DSDT 條件式裡的 `_S3`。需要 `acpi/tables-linux/DSDT.dsl`（在 Mac 上，gitignore）。
- `hib-test.sh off` 已跑（04:3x）：disablesleep 1、boot-args 的 `-v`、`debug=0x100` 回來（重開後生效）。

## 第 3b 步：SSDT-S3（`acpi/SSDT-S3.dsl`、`acpi/s3.sh`）

- DSDT（`acpi/tables-linux/DSDT.dsl`，在 Mac 上）第 860–871 行：`If ((CNSB == Zero)) { If ((DAS3 == One)) { Name (_S3, Package (0x04) { 0x03, 0x03, Zero, Zero }) } }`；
  `CNSB`、`DAS3` 在第 356、358 行（8-bit 欄位）。`_S4`（0x04, 0x04）無條件存在。
- 660m-Metal 的 `dist/acpi/SSDT-S3.dsl` 處理的是一模一樣的條件式（作者記錄：沒有它時 "every sleep attempt ends in kPMPCIUnsupported"，加上後 S3 有進入）。
  照它寫 FW13 版：Darwin 下 `If (LNot (CondRefOf (\_S3)))` 才建立 `\_S3 = {3, 3, 0, 0}`；`\_SB.FWS3` 的 `_STA` 露出 DAS3／CNSB。
  這裡用 iasl 20230628 `-vx 6142` 編過：0 error、172 bytes。
- 加在 ACPI.Add 最後；備份 `config.plist.bak-s3`。

### 第二次測試（2026-11-25 04:4x）：寫了映像、開機有進度條但還原失敗；**目前 macOS 開不進去（停在這裡）**

- 先有一次跟休眠無關的 panic：04:39 重開機時 AirportMtkWlan `mwx_dma_tx_cleanup` mbuf 重複釋放（HANDOFF 有記）。
- 04:4x `sudo pmset sleepnow`（Wi-Fi 已關）：電源燈沒熄，機器直接重開到 systemd-boot → 選 OpenCore → 韌體 "Default Boot Device Missing or Boot Failed"；
  再選 OpenCore → boot.efi「電腦因問題重新開機」畫面（上一次結束是 panic）→ 按鍵 → **出現還原進度條，跑到一半** → 又是 "Boot Failed"。
- 推論（未證實）：睡眠流程有走到寫映像（SSDT-S3 生效後不再被 kPMPCIUnsupported 擋），途中或寫完後 panic → 重開；NVRAM 有休眠金鑰／boot-image，
  `HibernateSkipsPicker = true` 讓 OpenCore 每次都直接交給 boot.efi 還原，映像不完整 → 失敗 → 回韌體。panic 內容還沒看到（要進 macOS 才讀得到）。
- **下一步（CachyOS）**：列出並刪掉 Apple GUID `7C436110-AB2A-4BBB-A880-FE41995C9F82` 下的 `boot-image`、`boot-signature`、`boot-switch-vars`、
  `IOHibernateRTCVariables` 等 efivars，讓 OpenCore 正常開機；進 macOS 後讀 panic、`hib-test.sh off`。
  如果刪了還是不行：CachyOS `sudo cp /boot/EFI/OC/config.plist.bak-hib2 /boot/EFI/OC/config.plist`（拿回 HibernateSkipsPicker=true 之前？不是——bak-hib2 是 on 之前的，
  仍是 SkipsPicker=true；要關掉 SkipsPicker／HibernateMode 用 bak-hib1，那份也沒有 PhxSleepPolicy 和 SSDT-S3）。
- 目前 macOS 端的設定：`disablesleep 0`、hibernatemode 25、sleep 0（hib-test on 的狀態）、boot-args 沒有 -v／debug=0x100。

### 2026-11-25 白天：macOS 開不進去的真正原因是 Wi-Fi 驅動開機 panic（不是休眠映像）

- CachyOS 看 Apple GUID 的 efivars：**沒有** `boot-image`／`boot-signature`／`IOHibernateRTCVariables` → 更正：昨晚的進度條是一般開機的進度條，不是在還原映像。
- 有 `AAPL,PanicInfo0000`–`0006`（每段 768 bytes，xnu `packA` 的 7-bit 壓縮）。在 CachyOS 用 python 解出來（一行指令見對話；先用模擬資料驗證過）：
  `assertion failed: MEXT_REF(m) != 0`（uipc_mbuf.c:1074），backtrace：`AirportItlwm::start` → `mwx_attach` → `mwx_init_hardware` →
  `mt7921_mcu_init` → `mwx_load_firmware` → `mwx_mcu_send_firmware` → `mwx_dma_tx_cleanup` → `m_freem`。**開機時**載入 Wi-Fi 驅動就 panic → 循環。
- 跟 PR #20 docs/SLEEP.md 寫的一樣：睡眠中途失敗會讓 MT7922 停在異常狀態，重開機不會好，要完全斷電（關機、拔電、按住電源 20 秒）。
- 下一步：完全斷電再開 macOS；不行就從 CachyOS 停用 AirportMtkWlan（Kernel.Add）讓 macOS 不帶 Wi-Fi 開機。
- 之後的休眠測試要避開 Wi-Fi 驅動：測試前不只關 Wi-Fi，可能要讓驅動在睡眠前卸載或乾脆停用 kext（待定）。
- **2026-11-25 21:2x 恢復**：完全斷電（關機、拔電、按住電源 20 秒）後 macOS 開得起來（第一次開機顯示「因問題重新開機」，是 NVRAM 裡那份 panic，
  存成 `Kernel-2026-11-25-212933.panic` 後清掉）。`hib-test.sh off` 已跑：SleepDisabled 1、hibernatemode 0、boot-args 還原（下次開機有 -v）。
  Wi-Fi 正常：en4 192.168.0.229，AirportMtkWlan 有載入。
- 第二次測試睡眠途中到底發生什麼，看不到了：NVRAM 的 PanicInfo 後來被開機時的 Wi-Fi panic 蓋掉。
- **下次測試前**：`hib-test.sh on` 現在也會停用啟用中的 `*Airport*` kext（要剛好一個，否則停止），測試期間 macOS 沒有 Wi-Fi；
  `off` 從 bak-hib2 還原整份 config，Wi-Fi kext 一起回來。這樣睡眠失敗不會把網卡弄卡住，也能把 Wi-Fi 從原因裡排除。

### 第三次測試（2026-11-25 21:45，Wi-Fi kext 停用）：驅動都斷電了、金鑰寫了，之後卡住

- `hib-test.sh on` 後重開，第一次選 OpenCore 又是 "Boot Failed"（這次**沒有** panic；原因不知道），再選一次正常開機。
  確認：AirportMtk 沒載入、`phxsleep_installed = 1`、SleepDisabled 0、hibernatemode 25。
- 21:45:23 `Entering Sleep state due to 'Software Sleep'` → 電源燈一直亮、螢幕全黑 → 21:51 強制關機。重開正常進 macOS（Wi-Fi 沒載入，網卡沒卡住）。
- **`nvram phx-sleep-note = "1 44 1"`**：PhxSleepPolicy 的 `setPowerState(0)` 跑了一次，當時 `IOHibernateRTCVariables` 長度 44（金鑰有產生），抄進 NVRAM 1 次。
  這個變數能留到下次開機，表示之後 kernel 的 NVRAM sync（`IOHibernateSystemHasSlept()`）也跑了。
  → **驅動斷電、金鑰、NVRAM sync 都過了；卡在寫映像或最後斷電（進 S4）**。
- 開機後 NVRAM 沒有 `boot-image`／`IOHibernateRTCVariables`，`IOHibernateState = 0`：推論 OpenCore／boot.efi 讀到了、發現映像不完整（映像標頭最後才寫）就丟掉、正常開機。未證實。
- `/var/vm/sleepimage` 的 mtime 還是 21:39（建檔時間）：休眠是用 polled I/O 直接寫磁碟區塊，不經過檔案系統，mtime 不會變，**不能拿來判斷**。
- 還不知道是「寫得很慢」還是「真的卡死」。下一次：同樣流程，插電、少開程式，**等 20 分鐘**再判斷。

### 第四次測試（2026-11-25 21:56）：約 2 分鐘後自己重開，沒有 panic；**映像沒寫完**

- 21:56:16 `Entering Sleep state` → 21:58:20 已經是新的開機（中間韌體 "Boot Failed" 一次）。DiagnosticReports 沒有新 panic。
- `/var/vm/sleepimage` 第一頁：只有 offset 0x58 是 `9d be e0 f1` = `kIOHibernateHeaderOpenSignature`（xnu `IOHibernatePrivate.h`），其他全 0。
  xnu `IOHibernateIO.cpp`：`IOHibernateSystemSleep()` 打開檔案時用 Open 簽章寫 extent 資訊，映像寫完才會寫 `kIOHibernateHeaderSignature`（0x73696d65）。
  → **`hibernate_write_image` 沒有寫完**（第三次卡住、第四次重置，都在寫映像的階段，或寫之前的 polled I/O 準備）。
- 寫映像時 xnu 會停住其他 CPU、只留一顆用 polled I/O 寫磁碟。嫌疑（都未證實）：
  1. `AMDRyzenCPUPowerManagement`（[39]）用 `pmKextRegister` 掛進 xnu 的 CPU 電源管理，停 CPU 時會經過它；
  2. NVMe 的 polled I/O；
  3. VoodooI2C 輪詢（`-vi2c-force-polling`）等在這個階段還在動的東西。
- 下一次：先停用 [39]、[40]（`power/hib-nopm.sh`，只在測試模式用，`hib-test.sh off` 會一起還原），其他不變。
- 也已清除 NVRAM `phx-sleep-note`，下次的值一定是新的。

### 第五次測試（2026-11-25 22:1x，Wi-Fi kext、[39][40] 都停用）：暫停

- `sleepnow` 後 8 分半：電源燈亮、風扇轉、螢幕黑（CPU 還在跑）。使用者決定到此為止，強制關機。
- 結果（映像標頭、phx-sleep-note）還沒讀；下次開始時先跑：
  `sudo dd if=/var/vm/sleepimage bs=4096 count=1 2>/dev/null | xxd -l 96 | tail -1; nvram phx-sleep-note`
- 暫停時要做：`hib-test.sh off`（還原 bak-hib2：Wi-Fi kext、[39][40]、-v／debug=0x100 都回來；disablesleep 1）。
- 之後要繼續的方向：映像寫入階段卡住／重置（嫌疑：NVMe polled I/O、VoodooI2C 輪詢、其他在 polled 階段還在動的驅動）。
