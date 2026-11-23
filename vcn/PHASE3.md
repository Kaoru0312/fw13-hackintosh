# 硬解階段 3 可行性研究：讓 VideoToolbox（Safari / YouTube / QuickTime / 動態桌布）用 VCN

日期 2026-11-22，macOS 26.6（25G72），只讀研究，沒改任何系統設定。

## 結論（先講）
**以目前的架構，不可行到「不值得做」的程度。** 唯一技術上走得通的路（路線 A）要在 kext 裡重做 Apple 的 IOAccelerator 影片介面，規模比階段 1–2 全部加起來大一個數量級，而且全是逆向工程。建議硬解停在階段 2，心力轉回續航。

## 1. 這台現在怎麼解碼（`vcn/phase3/vtprobe.m`，輸出 `vtprobe-1122.txt`）
- `VTIsHardwareDecodeSupported`：H.264 / HEVC / VP9 / AV1 / MPEG-4 / ProRes **全部 0**。
- 系統解碼器清單（29 個）沒有任何 GPU 解碼器：H.264 是 `VCP AVC Decoder`（軟體）、HEVC 是 `VCP HEVC Decoder`、AV1 是 `SW AV1 Decoder`。
- 建 H.264 session：不要求硬體 → 成功、`UsingHardwareAcceleratedVideoDecoder = 0`；要求硬體 → `-12906`（kVTCouldNotFindVideoDecoderErr）。
- → 現在所有影片（含 YouTube、Aerial 桌布）都是 CPU 軟解。
- 意外發現：任何用到 VideoToolbox/Metal 的行程都會載入 nullarc 的 Metal 驅動 `.../PhxGPU/NVMTLDriver.bundle`（偽裝名稱），它底下是 `libvulkan_radeon.dylib`（RADV），印出 `radv-darwin: native kext: ABI 1.12, build 34, VMID 8 ...`。也就是說 nullarc 的 Metal 是「Metal → RADV → 自家 kext 的私有 ABI」，**不是** Apple 的 IOAccelerator family。

## 2. macOS 怎麼選硬體解碼器
- Intel/AMD Mac 上 H.264/HEVC 硬解由 `AppleGVA.framework` 負責。它的字串顯示流程：讀 `board-id` → `LoadAllGPUAccelerators` 掃 IORegistry 的加速器節點，讀 **`IOVARendererID` / `IOVARendererSubID`** → 依 ID 載入對應的 VA 驅動 bundle（`/System/Library/Extensions/AMDRadeonVADriver2.bundle` 等）。另有 `gvaForceAMDAVCDecode` / `gvaForceAMDHEVCDecode` 等預設值開關（WhateverGreen 的 shikigva 就是動這些）。
- 這台：PhxBringup 的 IOAccelerator 節點只有 `MetalPluginName = NVMTLDriver`、`IOGLBundleName`，**沒有 `IOVARendererID`** → AppleGVA 不會載任何 GPU 解碼器。
- AMD VA 驅動（`AMDRadeonVADriver2` 7.1.6，在 dyld shared cache 內）還在 macOS 26 裡。它匯入的是 IOAccelerator 私有 API：`IOAccelDeviceCreate`、`IOAccelResourceCreate`、`IOAccelSharedCreate`、**`IOAccelVideoContextCreate / SubmitDataBuffers / GetSidebandBuffer`**、`IOSurfaceBindAccel` 等 → 它預期底下是 Apple 的 AMDRadeonX6000.kext（IOAcceleratorFamily2 的子類別）提供的 video context user client。
- 驅動內的類別：`Vcn3DecCommand`、`AvdHevcDecDataProcessor`、`AvdVcnAv1DecDataProcessor`、`Uvd7Command`……→ 會產生 VCN 2/3 世代的 decode ring 命令。Phoenix 是 VCN 4.0.2，Linux 只走 unified queue（沒有獨立 decode ring）。

## 3. 可能的插入點與代價
| 路線 | 做法 | 結果 |
|---|---|---|
| A. 冒充 AMD 加速器 | kext 加上 `IOVARendererID`，並實作 IOAcceleratorFamily2 的 device / shared / resource / **video context** user client，讓 AMDRadeonVADriver2 以為底下是 AMDRadeonX6000；再把它送來的 VCN3 decode 命令（GPCOM 暫存器寫入 + msg/DPB/target 位址）轉成 VCN4 unified queue 的 `decode_buffer` IB | 技術上唯一可能可用、對 Safari/桌布全部生效的路。但：IOAccelVideoContext 的 sideband/data buffer 格式完全沒文件、要逆向 AMDRadeonX6000 的對應程式；IOAccelResource 記憶體管理要跟 nullarc 自家的 GEM 並存；IOSurface 要能 bind 到我們的 GPU 位址；HEVC 還有 board-id/DRM（ASMF、PSP CP）檢查。估計數週到數月、成功率低。 |
| B. MediaExtension 解碼器（macOS 15+ `MEVideoDecoder`） | 寫一個 App Extension 解碼器，內部呼叫 VCN | 只有 app 主動呼叫 `VTRegisterProfessionalVideoWorkflowVideoDecoders` 才會載入，Safari/桌布不會；設計上是給系統不支援的 codec 用，蓋不掉內建 H.264/HEVC；extension 在沙盒裡，不能開任意 kext user client。**不可行。** |
| C. 注入 / 掛鉤 VideoToolbox | 用 dyld 注入或 Lilu 類的使用者空間 patch 換掉 VCP 解碼器 | Safari 的 WebContent / GPU 行程是 hardened runtime + library validation，要關 SIP/AMFI 才行，等於降低整台安全性，而且每次系統更新都會壞。**不建議。** |
| D. 第三方 `/Library/Video/Plug-Ins` 解碼器 | 舊式 VT decoder 外掛 | 同 B，只在專業工作流程註冊時載入，內建 codec 優先。**不可行。** |
| E. 只做 Vulkan（階段 2c） | mpv `--hwdec=vulkan` / ffmpeg 用 nullarc 的 RADV | 不碰 VideoToolbox，只對自己用 mpv 播本機檔案有用。仍是唯一「中等成本」的選項。 |

## 4. 對動態桌布的意義
- Aerial（影片桌布）目前 CPU 軟解 HEVC/H.264。要讓它硬解只能走路線 A。
- 比較實際的做法是**直接量它的耗電**：若 Aerial 比靜態桌布多很多瓦，就改用 HEIC 時間動態桌布（不需解碼）或靜態桌布；硬解不是解法。

## 留存
- `vcn/phase3/vtprobe.m`：VideoToolbox 探測工具（`clang -fobjc-arc -framework Foundation -framework VideoToolbox -framework CoreMedia vcn/phase3/vtprobe.m -o vcn/phase3/vtprobe`）。
- 階段 1–2 的成果（VCN 啟動、unified queue、MMHUB page table、斷電恢復）若哪天做路線 A 或 E 都會直接用到。
