# GFXOFF 移植研究（2026-11-24，只做研究，還沒改任何東西）

目標：閘控之後閒置封裝約 8.0 W（`HANDOFF.md` 0c），CachyOS 約 5.5 W。上游在 8745HS 上，SDMA 解除 halt 之後再開 GFXOFF，又省了約 1 W。

## 上游來源

| 項目 | 來源 | 狀態 | 上游量到 |
|---|---|---|---|
| SDMA0 解除 halt | [nullarc#24](https://github.com/luuumi-dev/nullarc/pull/24) `37a7b16`、`0a3bd8a`（mesboot `sdma_unhalt()`） | open；第二個 commit 改成預設關（`MESBOOT_SDMA=1` 才做） | 8745HS 閒置 6.5 → 5.8 W；`RLC_GPM_STAT` 0x00140016 → Linux 的 0x000c001a |
| GFXOFF | [nullarc#25](https://github.com/luuumi-dev/nullarc/pull/25) `c9b0abc`、`4c12d28`、`7b656fa`（PhxBringup） | **closed，沒合併**，關閉原因不知道 | 8745HS 閒置 6.0 → 4.9 W |

### 為什麼 FW13 之前送 0x19 沒效果（推論）

`37a7b16` 的 commit 訊息：PSP 有載入 SDMA 韌體，但 `SDMA0_F32_CNTL.HALT` 一直是 1。RLC 在做粗粒度時鐘閘控（CGCG）之前會問每個引擎，
halt 中的 SDMA 永遠不回答（`SDMA0_STATUS_REG.CGCG_FENCE` = 0），所以 `RLC_RLCS_CGCG_REQUEST` 一直是 3，兩個 GFX 時鐘都不會停。
`c9b0abc` 另外寫明：GFXOFF 除了 SMU 的 AllowGfxOff(0x19)，還要驅動先設 `RLC_PG_CNTL`（0xEC43）= 1、`RLC_PG_DELAY_3`（0xEC78）。
FW13 在 11-21 只送了 0x19，這兩個條件都沒有。

推論：FW13 這次閘控省下的 2 W，來自 MGCG／FGCG 這類不用 RLC 握手的部分；CGCG 可能還沒真的生效，要等 SDMA 解除 halt。
這一點還沒驗證，階段 0 的讀值可以確認。

### 風險（都出自上游）

- `0a3bd8a`：ACEMAGIC RX16（Ryzen 7 255）在 SDMA 運作時，45 分鐘內自己重開 3 次，SDMA 保持 halt 時 0 次，原因不知道；WUJIE15XA 跑 13 小時沒事。所以上游改成預設關。
- `c9b0abc`：GFX 斷電時寫入的 GC 暫存器會遺失。曾經在斷電時綁定 VMID，第一個 IB 就 fault、佇列卡死；所以 kext 碰 GC 暫存器或 ring 之前，一定要先 `gfxOn()`（送 0x1A、等 `GRBM_STATUS` 不是 0）。
- `4c12d28`：GFX 斷電狀態下闔上螢幕進入休眠，機器會重開。FW13 不睡眠，但闔上螢幕的路徑還是要測。

## 分階段計畫

### 階段 0：只讀確認（不用重編，沒風險）

| 暫存器 | 絕對位址（dword） | 換算 | 預期 |
|---|---|---|---|
| SDMA0_F32_CNTL | 0xF89A | GC 段 1 基底 0xA000 + 0x589a（`37a7b16`） | bit 0（HALT）= 1 |
| SDMA0_CNTL | 0x127C | 段 0 基底 0x1260 + 0x001c | Linux 是 0x10002440（`37a7b16` 註解） |
| SDMA0_STATUS_REG | 0x1285 | 0x1260 + 0x0025 | bit 11（CGCG_FENCE）= 0 |
| SDMA0_RLC_CGCG_CTRL | 0x12BC | 0x1260 + 0x005c | bit 1 = 1（gpucg 已經設了） |
| RLC_GPM_STAT | 0xEE6B | 0xA000 + 0x4e6b（780m-hackintosh `gfx_v11_0.h` 第 83 行，引 Linux gc_11_0_0_offset.h） | 上游 halt 時 0x00140016 |
| RLC_PG_CNTL | 0xEC43 | `c9b0abc` | 0（沒開 power gating） |

段 0 / 段 1 基底取自 nullarc PhxBringup 的註解「GC 11.0.1 registers (segment 0 base 0x1260, segment 1 base 0xa000)」，FW13 的 `mesboot.c`
`sched_test()` 的 `gcb[]` 也是 `{0x1260, 0xA000, …}`。gpucg 用的 0xEC48（= 0xA000 + 0x4c48）就是這樣算的，已經在 FW13 上驗證過。

**階段 0 結果（2026-11-24）**：`0xF89A = 0x08084001`（HALT = 1）、`0x127C = 0x00002440`（缺 bit 28）、`0x1285 = 0x46dee557`（bit 11 CGCG_FENCE = 0）、
`0x12BC = 0x00400002`、`0xEE6B = 0x00140016`、`0xEC43 = 0`。跟上游修正前的狀態**完全一樣**（`RLC_GPM_STAT` 連數值都相同）。→ 進階段 1a，腳本 `gpu/sdma-test.sh`。

### 階段 1：SDMA 解除 halt（只要 3 個暫存器寫入）

上游在 mesboot 裡做，時機是 MES 初始化之前。兩種做法：

- **1a. 執行期用 phxctl 寫**（不用重編、重開機就恢復）：寫 `0xF89A` 清 bit 0、`0x127C` 設 bit 28。上游沒試過在佇列都建好之後才解除 halt，安不安全**不知道**。
  還原就是把 HALT 寫回 1。
- **1b. 照上游放進 FW13 的 mesboot**（`MESBOOT_SDMA=1` 才做），phxboot 帶這個環境變數。要重編 mesboot（FW13 自己的 port，改動約 10 行）。

先做 1a 量功耗。如果有效，而且用一段時間沒有自己重開，再改成 1b 或開機自動套用。

### 階段 2：PhxBringup GFXOFF（要重編 kext）

**基底的問題**：FW13 跑的是 release v0.4.0 二進位，改了拓撲表 10 bytes（`gpu/topology-patch.py`，release sha256 `4a88035f…`）。
repo 裡的 `nullarc-kext/phxbringup/PhxBringup.cpp` 跟 nullarc main `b787e24`（2026-11-14）一模一樣，比 v0.4.0-alpha 標籤多了 4 個檔案、
465 行／刪 139 行（IORWLock、client reaping 等），`topology-patch.py` 的註解就是因為這樣才不重編。所以要用 **`v0.4.0-alpha` 標籤**的原始碼當基底：

1. 先確認可重現：用 Mac 上的 Command Line Tools 和 MacKernelSDK 編 `v0.4.0-alpha` 的 PhxBringup，sha256 要等於 `4a88035f…`。
   mechrevo `docs/known-issues.md` 說他們編出來跟 release 逐 byte 相同；FW13 還沒試。不同就停在這裡。
2. 拓撲表：把 `topology-patch.py` 換的那張表，改成原始碼裡 `src/amd/phx_topology.h` 的 `g_phx_780m_default`。編出來要跟
   ESP 上目前用的 binary 逐 byte 相同（只差這張表）。Info.plist 沿用 ESP 上那份（IOPCIMatch 已加 `0x15bf1002`）。
3. 套 PR #25 三個 commit。v0.4.0 標籤裡沒有 `suspended`（那是 PR #20 休眠才加的），相關判斷要拿掉；其他用到的
   （`isSleeping`、`hangTick`、`gq[1]`、`queueFence`、`killWaves`、`vmFlushTlb`、`smuMessage`、`adoptQueue`）標籤裡都有。
4. FW13 自己要加的（上游沒有）：
   - `readRegs()` 和 `writeReg()`（phxctl `regs`／`wreg` 走的路）也要先 `gfxOn()`。否則 GFX 斷電時，`gpucg.sh status` 會讀到 0，寫入也會遺失。
   - 不用 boot-arg `phxgfxoff=1`。改成 phxboot 跑完 `gpucg.sh on` 之後，再 `sysctl debug.phx_gfxoff=1`。原因：GFXOFF 如果比閘控先啟動，
     閘控的寫入可能會遺失；另外 GFX 斷電再上電之後，閘控設定還在不在，**不知道**（上游 build 37 的 kext 每 16 個 tick 檢查 override、
     被清掉就重設，代表至少「重新初始化」會清掉）。所以要加一個計數器：每次 `gfxOn()` 之後讀 0xEC48，如果變回 0x607ff 就記下來。
5. 編號改成 build 34 之外的值（例如 `PHX_KEXT_BUILD 134u`），用 `ioreg … phx-build` 確認載入的是新版。
6. 安裝：換 ESP 上的 PhxBringup.kext（先備份），CachyOS 還原指令照 HANDOFF 的格式準備。

### 驗收

- 功耗：`power/idle-measure.sh`，跟 8.03 W（閘控後中位數）比。
- 穩定性：mtlprobe、Safari 播影片、開關 App、螢幕關閉、闔上螢幕；`sysctl debug.phx_gfxoff_allows debug.phx_gfxoff_wakes` 要一直增加（代表真的有進出 GFXOFF）。
- 長時間：至少跑幾個小時，注意有沒有像 RX16 那樣自己重開。
