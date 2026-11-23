# 硬解階段 1：在 macOS 上啟動 VCN 4.0.2（設計）

目標：證明 VCN「活著」——載入韌體、開電、建立 unified ring，送一個 `VCN_ENC_CMD_END`，看到 RPTR 前進。這一步還不解碼任何影片。

## 關鍵發現：不用寫 kext
PhxBringup 的除錯介面（`phxdebug=1`、root，user client `N48N`）已經有：
| 功能 | selector | phxctl 指令 |
|---|---|---|
| 讀暫存器 | 2 | `regs` |
| 寫暫存器（任意 MMIO） | 108 | `wreg` |
| 讀 / 寫 BAR0 VRAM（256 MiB 窗口） | 102 / 109 | `vram` / `vramw` |
| 暫存韌體到 fw_buf + PSP `LOAD_IP_FW` | 104 / 105 | `stage` / `loadfw` |
| SMU 訊息（白名單，沒有 PowerUpVcn） | 100 | `smu` |

SMU 的 `PowerUpVcn (0x07)` / `PowerDownVcn (0x06)` 不在白名單 → 直接寫 MP1 mailbox 暫存器（MSG `0x16282`、ARG `0x16292`、RESP `0x1629A`），流程跟 kext 的 `smuMessage` 一樣。
所以整個階段 1 用一個使用者空間工具 `vcn/vcnctl.c` 完成，不動 OpenCore、不動 kext、不在開機流程裡。重開機後 VCN 自動回到斷電狀態。

## 流程（照 Linux `vcn_v4_0.c`：PSP 載入 + DPG + indirect SRAM，Phoenix 走的路徑）
1. **PSP 載韌體**：`vcn_4_0_2.bin[0x100 : +0x62890]` 暫存到 fw_buf+0，`LOAD_IP_FW` type 13（`GFX_FW_TYPE_VCN`），PSP 把它放進 TMR。
2. **SMU PowerUpVcn**（參數 `inst << 16` = 0）：VCN 預設是斷電的。
3. **fw_shared**（VRAM）：`UNIFIED_QUEUE | SMU_DPM_INTERFACE`、`sq.is_enabled = 1`、`smu_interface_type = APU`；4.0.2 再加 `DRM_KEY_INJECT` + `ASD_HANDSHAKING`（可用 `--no-drmkey` 關掉）。
4. **UVD_POWER_STATUS**：anti-hang（低 2 bit = 1），再設 `PG_MODE | PG_EN`（直接寫暫存器）。
5. **DPG SRAM 清單**：把 `start_dpg_mode` 裡 `WREG32_SOC15_DPG_MODE(..., indirect)` 的 27 組 (內部位址, 值) 組起來，暫存到 fw_buf+0x100000，`LOAD_IP_FW` type 49（`VCN0_RAM`）讓 PSP 套用。內容：VCPU_CNTL、MASTINT、LMI_CTRL、MPC、mc_resume（stack/context/fw_shared 的 cache window，韌體 window 由 PSP 填）、GFX10_ADDR_CONFIG（0x242）、LMI_CTRL2、MASTINT_EN。clock gating 段 Phoenix 有 `VCN_MGCG` → Linux 直接略過，這裡也略過；RAS 段 APU 不支援，略過。
6. **unified ring**：`UVD_RB_BASE_LO/HI`、`UVD_RB_SIZE`、`VCN_RB_ENABLE`（先關 RB1）、fw_shared `queue_mode |= RING_RESET`、`RPTR = WPTR = 0`、開 RB1、清 `RING_RESET | DPG_HOLD_OFF`。**不設 doorbell**：Linux 的 `set_wptr` 在沒有 doorbell 時就直接寫 `UVD_RB_WPTR`。VCN4 的 DPG pause 由韌體自己處理（`amdgpu_vcn_ring_begin_use`：「VCN4 and above will be handled by FW」）。
7. **ringtest**：在 ring 寫 `VCN_ENC_CMD_END` + 63 個 `NO_OP`（align_mask 0x3f），`WPTR += 64`，2 秒內看 `RPTR` 有沒有動。
8. **down**：等 `POWER_STATUS == 1`、關 RB1、清 `PG_MODE`、SMU `PowerDownVcn`。

## 位址與記憶體
- VCN 暫存器：IP discovery VCN inst0 seg1 = `0x7e00`（這裡用到的暫存器 BASE_IDX 都是 1）。來源是 Firebat 780M 的 dump；FW13 同一顆 Phoenix 晶片（PCI 0x15bf），nullarc 的 GC `0x1260`/`0xA000`、MP1 `0x16000` 也是同一份表，在這台都正確。
- DPG 內部位址：照 `SOC15_DPG_MODE_OFFSET`（video range `0x1fb00..+0x2600` → `- 0x1fb00`；aon range `0x1f800..+0x600` → `- 0x1f800 + 0x30000`；video 先判斷）。已用主機端小程式驗算：VCPU_CNTL → `0xd6`、GFX10_ADDR_CONFIG → `0xc042`。
- VRAM（BAR0 byte offset，MC = `0x8000000000` + offset）：

| 區段 | 位置 | 大小 |
|---|---|---|
| 現有：console FB | 0 – 0xFA0000 | |
| 現有：PSP ring/cmd/fence | 0x1100000 – +0x9000 | |
| 現有：fw_buf（開機時暫存韌體，之後閒置） | 0x4000000 – +16 MiB | |
| 現有：TMR（PSP 擁有） | 0x8000000 – +64 MiB | |
| **新：VCPU BO（stack 128K + context 512K）** | 0xC000000 | 0xA0000 |
| **新：fw_shared** | 0xC0A0000 | 4 KiB（結構 148 bytes） |
| **新：unified ring** | 0xC100000 | 16 KiB |

  nullarc 的 GEM「VRAM」BO 其實是系統記憶體（`IOBufferMemoryDescriptor`，只做帳），不會落在這段。`vcnctl check` 原本要求 0xC000000 起 2 MiB 全是 0；第一次實測（2026-11-22 12:37）整段都非 0——carve-out 開機不清 0、熱重開後 CachyOS 的殘留還在。改成讀兩次隔 3 秒、完全沒變才繼續，`up` 先把 VCPU BO / fw_shared / ring 清 0（Linux `amdgpu_vcn_resume` 也會 memset VCPU BO）。

## 安全措施
- `vcn-test.sh` 先跑只讀的 `check`；沒過就停，什麼都不寫。
- 排 4 分鐘後自動重開（同 `bringup5.sh`），跑完正常就取消。GPU 若卡死、使用者空間還活著，至少會自己重開。
- 只碰 VCN 暫存器、SMU mailbox、上表的 VRAM 新區段、PSP（透過 kext 既有的 ring）。不碰 GFX、DCN。
- 最壞情況：GPU/系統卡住 → 強制關機重開 → VCN 斷電、phxboot 可能自動建立 `phxboot-off`（照之前的方式移除）。CachyOS 不受影響。

## 已知風險 / 不確定處
1. **DRM key / ASD**：4.0.2 的 fw_shared 會要求「ASD handshaking」，但 nullarc 沒載 ASD（PSP 的 TA）。韌體可能卡住或拒絕工作 → 先用預設（同 Linux）測，不行就 `--no-drmkey`。
2. **沒有 doorbell**：如果韌體只認 doorbell，ringtest 會失敗；下一步要設 NBIO 的 VCN doorbell range（`nbio_v7_7_vcn_doorbell_range`）+ `VCN_RB1_DB_CTRL`，用 kext 的 doorbell selector 寫。
3. **SMU mailbox 跟 kext 搶**：kext 有 `smuLock`，我們直接寫暫存器沒鎖；只要測試時沒有別人送 SMU 訊息就沒事（phxboot 只在開機送；Power Gadget 要關）。
4. **PSP 在 GFX 運作中載 VCN 韌體**：Linux 在 resume 時也這樣做，應該沒問題。
5. PhxBringup v0.4.0（ESP 上的 release 版）跟 repo 裡較新的原始碼可能不完全一樣；`phxctl` v0.4.0 binary 有 `wreg`/`vramw`/`loadfw` 字串，selector 應該一致。

## 成功之後（階段 2 預告）
- RADV 送的是 VCN unified queue 的 IB（含 signature / engine info / decode buffer），要讓 nullarc winsys 放行 `AMDGPU_HW_IP_VCN_ENC` 的 IB，在 kext 裡轉成 VCN ring 上的 `VCN_ENC_CMD_IB` + fence。這一步就需要改 kext 了。

## 備案 1b：如果 ringtest 失敗、懷疑要 doorbell（已查好，尚未實作）
- Phoenix 的 CG/PG 旗標（`soc21.c` `IP_VERSION(11, 0, 1)`）已確認：`AMD_CG_SUPPORT_VCN_MGCG`（→ 略過 DPG clock gating 是對的）、`AMD_PG_SUPPORT_VCN | VCN_DPG | JPEG`。
- doorbell index：`AMDGPU_NAVI10_DOORBELL64_VCN0_1 = 0x188`；unified ring `doorbell_index = (0x188 << 1) + 2 + 8*inst = 0x312`；NBIO range 起點 `(0x188 << 1) + 8*inst = 0x310`、SIZE 8。
- NBIO：`regGDC0_BIF_VCN0_DOORBELL_RANGE = 0x4f0af3`（BASE_IDX 3）；欄位 OFFSET `[11:2]`、SIZE `[20:16]`。Linux 用 `RREG32_PCIE_PORT/WREG32_PCIE_PORT`（PCIe port 間接 index/data，`nbio_v7_7_get_pcie_port_index_offset`），不是一般 MMIO → 要再查 index/data 暫存器位址才能用 `wreg` 做。
- ring 端：`VCN_RB1_DB_CTRL = (0x312 << 2) | EN(bit30)`；送命令時用 kext 的 doorbell selector（`doDbgDoorbell(index, value)`）寫 0x312。
