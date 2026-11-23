# 硬解階段 2：讓 VCN 真的做事（設計）

階段 1 已證明：韌體載得進去、VCN 開得了電、unified ring 會被讀（RPTR 0 → 0x40）。
階段 2 分三步，越後面越大：

| 步驟 | 目標 | 要改什麼 | 狀態 |
|---|---|---|---|
| 2a | 從使用者空間送一個真的 decode IB，看到 fence 寫回 | 只有 `vcnctl`（不動 kext） | ✅ 通過（2026-11-22 13:02） |
| 2b | IB 用 GPU 虛擬位址（行程的 page table），能讀寫系統記憶體 | 先 `vcnctl vmtest` 驗證，再搬進 kext | ✅ vmtest 通過（2026-11-22 13:09），kext 未做 |
| 2c | RADV 的 Vulkan Video 能送 decode 工作 | kext：放行 VCN IB + VCN queue；winsys 放行 | 暫緩（見 PHASE3.md） |

## 2a：decode IB + fence（`vcnctl ibtest`）
照 Linux `amdgpu_vcn_dec_sw_ring_test_ib`：送兩個 job，第一個帶「create session」訊息、第二個帶「destroy」訊息，每個 job 後面接 fence。

- ring 上一個 job：`VCN_ENC_CMD_IB(2)`、vmid 0、IB 位址 lo/hi、長度 → `VCN_ENC_CMD_FENCE(3)`、fence 位址 lo/hi、seq → `END(1)` → NOP 補到 64 對齊（`amdgpu_ring_commit` 的 `insert_end` + `align_mask 0x3f`）。
- IB 內容（unified queue）：checksum 標頭 `0x10, 0x30000002, sum, 39` + engine info `0x10, 0x30000001, 3(decode), 156` + `140, DECODE_BUFFER(1)` + `amdgpu_vcn_decode_buffer`（valid=MSG_BUFFER，msg 位址 hi/lo，pad 30）。長度 43 dw。checksum 已在主機端驗算（0x3c1201be）。
- create msg：`0x28, 0x38, 1, 0, handle 1, 0, 1, 0x28, 0x10, 0, 7(H.264), 0, 1920, 1088`；destroy：`0x28, 0x18, 0, 2, handle 1, 0`。
- **vmid 0**：不經 page table，直接用 MC 位址 → IB、msg、fence 全放 VRAM 窗口（ring test 證明 VCN 讀得到）。
- **HDP flush**：BAR0 寫入要寫 `phx-hdp-flush-dword`（0xE17）才保證落到 DRAM，跟 kext 敲 doorbell 前一樣。ring test 時沒做——NOP 是 0，讀到舊的 0 也會過，所以這次 IB 內容才是真的考驗。
- **不送 TRAP**（預設）：nullarc 沒有 IH ring，沒人收 VCN 中斷；fence 是 `FENCE` 指令自己寫的，跟 TRAP 無關。`--trap` 才送。
- VRAM 配置（都在 check 驗過的 2 MiB 內）：ring `+0xC100000`、fence `+0xC108000`、IB `+0xC110000`（兩個各 4 KiB）、msg `+0xC120000`（create）/`+0xC122000`（destroy）。

`vcn-test.sh` 現在是 check → up → ringtest → **ibtest** → down。

### 2a 可能的結果
- fence = 1、2 → VCN 韌體真的在跑、看得懂 unified queue 的 decode IB。
- fence 不動、RPTR 有動 → 韌體讀了 ring 但 IB 失敗：可能是 HDP、IB 位址、或 decode 引擎要 session context buffer。
- RPTR 也不動 → ring 被卡住（看 `UVD_STATUS`……但 DPG 下讀不到，要改用 `--no-drmkey` 比較）。

## 2b：GPU 虛擬位址（MMHUB）
RADV 的 IB、bitstream、輸出影像都是行程 page table 裡的 GPU VA，而且多半在系統記憶體（nullarc 的「VRAM」BO 也是系統記憶體）。

- **關鍵差異**：VCN 走 **MMHUB**，GFX 走 **GCHUB**。kext 的 `vmBind` 只寫 GC 的 `GCVM_CONTEXT{8..15}`（`0x28E8` / `0x2953` / `0x2973` / `0x2993`，invalidate engine 17）。VCN 用 vmid 8 會看到 MMHUB 那邊空的 context → page fault。
- **做法**（照 Linux：兩個 hub 共用同一份 page table）：`vmBind` 時把同一個 root（`c.phys | 3`）、CNTL、START/END 也寫進 MMHUB：
  - MMHUB 3.0.1 seg1 = `0x1A000`（kext 已用它讀 `MMMC_VM_FB_LOCATION_BASE 0x1A8EC`）
  - `MMVM_CONTEXT0_CNTL` `0x1A740 + vmid`
  - `MMVM_CONTEXT0_PAGE_TABLE_BASE_ADDR_LO32` `0x1A7AB + 2*vmid`（HI 是 +1）
  - `..._START_ADDR_LO32` `0x1A7CB + 2*vmid`、`..._END_ADDR_LO32` `0x1A7EB + 2*vmid`
  - TLB invalidate：`MMVM_INVALIDATE_ENG17_REQ` `0x1A763 + 17`、`ACK` `0x1A775 + 17`
  - `vmFlushTlb` 兩個 hub 都要做。
- **先只讀確認**：`sudo /Users/kaoru/fw13-hackintosh/vcn/vcnctl mmhub` 印 MMHUB 的 FB/AGP/system aperture 跟 16 個 context 的現況，跟 GC VMID8 對照。CNTL 欄位格式要對 `mmhub_3_0_1_sh_mask.h` 確認跟 GC 一樣再寫。
- PTE 格式兩個 hub 相同（gmc_v11）；`kPteSysFlags`（VALID|SYSTEM|SNOOPED，MTYPE 4）應可直接用，snooped 讓 VCN 讀到 CPU cache 裡的資料。

### 2b 實測發現與 `vcnctl vmtest`
- `vcnctl mmhub`（2026-11-22）：開機韌體只把 MMHUB 設成實體模式——`MX_L1_TLB_CNTL 0x501`（SYSTEM_ACCESS_MODE 0、沒有 ADVANCED_DRIVER_MODEL）、`L2_CNTL 0x80602`（L2 cache 關）、`L2_CNTL4 0xc1`（PDE/PTE 請求當實體）、invalidate range 0、預設頁 0、所有 context 停用。GC 那邊是 mesboot 照 Linux 設好的（0x1859 / 0x80e01 / 0x80130009 / 0x1）。
- 所以 2b 不只要寫 context，還要改 MMHUB **全域**設定。照 Linux `mmhub_v3_0_1_gart_enable` 算出來的值剛好全跟 GC 現值一樣。
- 對顯示的影響：掃描緩衝在 VRAM（`phxfb.cpp` 的 fBase，HDMI 是 fBase+16 MiB），落在 FB aperture 內；SYSTEM_ACCESS_MODE 3 下 vmid 0 的 FB 位址照樣走實體 → 理論上不影響畫面。預設頁原本是 0（= 系統記憶體第 0 頁，fault 會寫到那裡），改指向 VRAM 窗口內的 scratch 頁。
- `vmtest`：備份 19 個 MMHUB 暫存器 → 平面 PTE 表（VRAM +0xC180000，512 項；VA 0x40_0000_0000 + x → VRAM +0xC100000 + x，最後一頁 → SYSMEM selector 的系統記憶體頁，PTE SYSTEM|SNOOPED）→ 全域設定 → context 1（depth 0，CNTL 0x01fffe01）→ eng17 invalidate → job 1（vmid 1，fence 寫 VRAM）→ job 2（fence 寫系統記憶體）→ **還原全部暫存器**（`--keep` 才保留）。
- 用法：`sudo bash /Users/kaoru/fw13-hackintosh/vcn/vcn-test.sh --vm`。

## 2c：RADV → kext → VCN ring
- ABI 已經留好：`phxn_cs_ib` 有 `ip_type / ip_instance / ring`。兩處擋住：
  1. kext `doSubmit`：只收 `GFX(0)` / `COMPUTE(1)` → 加 `AMDGPU_HW_IP_VCN_ENC(4)`（unified queue 在 Linux 就是 VCN_ENC ring）。
  2. RADV winsys（nullarc 的 `libvulkan_radeon.dylib`，binary 裡的字串 `ib.ip_type != AMDGPU_HW_IP_GFX`）→ 要重編 nullarc 的 Mesa，或在 kext 端回報 queue 資訊讓 RADV 開 video queue。**原始碼不在這個 repo**，要先找 nullarc 的 Mesa 分支。
- kext 端：VCN ring 從 `vcnctl up` 搬進 kext（開機或第一次用時 up，閒置時 down 省電），submit 時在 VCN ring 寫 `IB(vmid, va, len)` + `FENCE(VRAM fence, seq)` + END，用 MMHUB 版 `vmBind`；完成判定沿用 kext 現在「輪詢 VRAM fence」的模型（不用中斷）。
- `patch_cs_in_place`（Linux `vcn_v4_0_ring_patch_cs_in_place`）：VCN4 的 decode IB 若含 AV1 encode session 要改走 instance 0；Phoenix 只有一個 instance，可忽略。
- 還要回報 `AMDGPU_INFO_HW_IP_INFO(VCN_ENC)`、`AMDGPU_INFO_VIDEO_CAPS`、`fw_version`，RADV 才會打開 video decode。

## 實用面（誠實說明）
macOS 的 Safari / YouTube / QuickTime 走 **VideoToolbox**，不是 Vulkan Video。2c 完成後，直接受益的是用 Vulkan 解碼的程式（例如 `mpv --hwdec=vulkan`、ffmpeg `-hwaccel vulkan`，要讓它們載到 nullarc 的 RADV）。讓 Safari 也硬解需要寫一個 VideoToolbox 解碼外掛，那是階段 3，規模更大。
