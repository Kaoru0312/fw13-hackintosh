# 硬解重新評估（2026-11-24，只做研究）

`vcn/PHASE3.md` 的結論是停在階段 2。這份根據兩個新參考重新評估：mechrevo-f7bsc（同一顆 Phoenix VCN 4.0.2）和
ryzenstatus-utils（VideoToolbox 解碼外掛）。

## 現有的拼圖

| 需要的東西 | FW13 自己有的 | 參考專案有的 | 缺的 |
|---|---|---|---|
| VCN 上電、韌體、unified queue、fence | ✅ 階段 1、2a（`vcn/vcnctl.c`，使用者空間經 PhxBringup 除錯介面） | mechrevo `phxbringup-vcn.patch` 搬進 kext（build 67） | — |
| VCN 經 MMHUB 讀行程的 GPU VA | ✅ 階段 2b（vmtest，使用者空間） | mechrevo patch 裡有 | kext 版 |
| kext 提供「送一張任意 H.264 frame 解碼」的介面 | ✗ | **公開的 patch 只到 build 67**：解碼只有「固定測試向量」（`PhxVcnDecodeTestVector.h`，864×480 一張 IDR）；任意尺寸的 NV12 介面只有**編碼**。BENCHMARKS.md 講的 build 75（真的解任意 H.264、1080p30 CPU −41%）**原始碼沒有公開**（`git log` 全部 19 個 commit 都查過，沒有解碼外掛或 build 75 的檔案） | 要自己寫 |
| H.264 位元流解析（SPS／PPS／slice header）→ VCN 的 decode message（`rvcn_dec_message_avc`）、DPB 管理 | ✗ | 沒有。可參考 Mesa `src/gallium/drivers/radeonsi/radeon_vcn_dec.c`（`get_h264_msg`）+ 一個 H.264 header parser | 要自己寫（最大的一塊） |
| VideoToolbox 解碼外掛的 ABI（`CMClassImplementations`、`CMDerivedObjectCreate`、`VTVideoDecoderClass`） | ✗ | ryzenstatus-utils `GPU/decode/av1/AV1VCNDecoder.c`（791 行，MIT），外掛結構可以照抄，解碼部分換成自己的 | 改寫 |
| 系統會載入未簽章外掛 | ? | ryzenstatus：放 `/System/Library/Video/Plug-Ins` 不檢查簽章（RX 6800 XT、26.7.3）。mechrevo：放 `/Library/Video/Plug-Ins` 的**編碼器**被簽章檢查擋掉 | FW13（26.6）沒驗證 |

其他確認過的事：

- mechrevo 的 `phxbringup-vcn.patch` 可以乾淨套在 nullarc **`v0.4.0-alpha` 標籤**上（`git apply --check` 通過），套在 repo 裡 `b787e24` 版的原始碼上則失敗。
  FW13 跑的就是 v0.4.0 release，所以基底跟 `gpu/GFXOFF-PLAN.md` 階段 2 一樣，兩件事可以共用同一個重編流程。
- FW13 的 `csr-active-config` = `7F080000`（= 0x87F），包含 0x800（CSR_ALLOW_UNAUTHENTICATED_ROOT，`csrutil authenticated-root disable` 設的就是這個位元）。
  nullarc 安裝時也已經改過系統磁碟區（`/System/Library/CoreServices/CoreTypes.bundle/.../PhxGPU`），所以寫入 `/System/Library/Video/Plug-Ins` 應該做得到（推論）。

## 先要回答的問題：值不值得

H.264 硬解只對「真的送 H.264 給 VideoToolbox」的播放有用。YouTube 在 Safari 上給的是 H.264（avc1）、VP9（vp09）還是 AV1（av01），**不知道**，
要在 FW13 上看（YouTube 影片按右鍵 →「詳細統計資料」→ Codecs 那一行）。
- 如果是 vp09／av01：H.264 解碼器對 YouTube 沒幫助。VCN 4.0.2 硬體支援 VP9 和 AV1 解碼，但這兩種的 message 格式和 parser 更複雜，ryzenstatus 的 parser（`av1parse.c`、`vp9parse.c`）可以參考，只是他們是交給 Apple 的 AMD 驅動，不是直接組 VCN message。
- 如果是 avc1：H.264 路線有意義。

## 工作量估計（推論，沒有實際數據）

依 FW13 階段 1–2 的經驗（一天內做完），以及 mechrevo 從 build 64 到 75 大約花了 1–2 天（commit 時間 11-22 05:07 → 11-23 15:51）：

1. kext：把 mechrevo build 67 的 VCN 部分搬進 v0.4.0 + 拓撲表 + 自己加「任意 frame 解碼」介面（輸入：bitstream、msg、DPB／輸出的 IOSurface → GPU VA）。
2. 使用者空間：H.264 parser + VCN message 組裝 + DPB；先做成命令列工具，拿 mechrevo 的 `vcn_quadrants.h264`、`fixture-*.h264` 對答案。
3. VT 外掛：照 ryzenstatus 的結構包起來，裝到 `/System/Library/Video/Plug-Ins`，用 `vcn/phase3/vtprobe.m` 和 mechrevo 的 `vt-bench.c` 驗收。
4. Safari 實測。

每一步都要在 Mac 上編譯、上機測，第 1 步要換 ESP 上的 PhxBringup（跟 GFXOFF 階段 2 一樣的風險和還原方式）。

另一個選項：向 mechrevo 作者詢問 build 75 的原始碼會不會公開（他們的 repo 是 MIT＋第三方授權）。這要使用者自己決定要不要開 issue。

## 2026-11-24 決定與第一步

- YouTube 在 Safari（FW13）用的是 **`avc1.640028`**（H.264 High profile、level 4.0），所以 H.264 路線對 Safari 的 YouTube 有用。
- 第一步不改 kext：在 FW13 自己的 `vcn/vcnctl.c` 加 `decodetest`，用使用者空間（PhxBringup 的除錯介面，跟階段 1–2 一樣）
  解一張固定的 H.264 畫面（libdrm 的 864×480 IDR 測試向量，`vcn/vcn_dec_vector.h`）。輸出 NV12 加總要等於 0x020345d8。
  這一步過了，就證明 FW13 的 VCN 解碼路徑（session、DPB、bitstream、target、feedback 這些 buffer 的格式）是對的，
  接下來才值得寫 H.264 parser（第 2 步）去餵真的影片。
- VRAM 用 +0x0D000000 起約 16 MiB（0xD000000–0xE008000，mechrevo 的 kext 也用這段）。寫入前先把整段讀兩次（間隔 3 秒）比雜湊，
  有變就停止、什麼都不寫。這段 FW13 上有沒有別的用途：不知道，靠這個檢查把關。
- 執行：`sudo bash /Users/kaoru/fw13-hackintosh/vcn/vcn-test.sh --dec`（check → 4 分鐘自動重開 watchdog → up → ringtest → ibtest → decodetest → down）。
  只在 Linux 用假的 Apple 標頭做過語法檢查，沒在 Mac 上編譯過。

## 第一步結果（2026-11-24 12:49，log `vcn/log-1124-124918.txt`）✅

`vcn-test.sh --dec`：up、ringtest、ibtest 都過；decodetest 的 VRAM 0xD000000–0xE008000 雜湊 3 秒內沒變，清 0 花 7.7 秒；
建立 session（fence 0x31，3 ms）→ 解碼（fence 0x32，3 ms）→ 關閉 session（fence 0x33，1 ms）。
**輸出 NV12 總和 0x020345d8 = 期望值**，非 0 位元組 622080 / 737280；feedback `0x2c 0x2c 0 1 0 1 …`。down 正常，WindowServer 正常。
→ FW13 的 VCN 4.0.2 用 libdrm 的 buffer 配置與 IB 格式，能解出正確的 H.264 畫面。畫面存在使用者 Mac 的 `vcn/dec-1124-124926.nv12`
（`vcn/nv12-to-pgm.py` 可轉成灰階圖看）。

下一步（第 2 步）：自己組 decode message。從 libdrm 向量的 message（236 bytes）+ parameters（3344 bytes）對照 Mesa
`radeon_vcn_dec.h` 的 `rvcn_dec_message_*` 結構，寫出「H.264 SPS／PPS／slice header → message」的產生器；先讓它對 libdrm 那張畫面產生
**跟向量逐 byte 相同**的 message（不用上機就能驗證），再拿 mechrevo 的 `vcn_quadrants.h264`（160×128）等單張 IDR 上機解碼。

## 第 2 步進度（2026-11-24）

- `vcn/h264/h264_parse.[ch]`：Annex B、SPS（含 scaling list fall-back）、PPS、slice header（含 ref list modification、pred weight table、
  dec_ref_pic_marking／MMCO）。mechrevo 三支測試檔（160×128、2048×1152、2560×1440，High profile、CABAC、8x8 transform）都解析成功，
  slice 的 first_mb 連續（例：2048×1152 共 8 個 slice，每個 1152 MB）。
- `vcn/h264/vcn_h264_msg.[ch]`：照 Mesa TIER0 組 create／decode message。用 libdrm 那張畫面的參數組出的 avc 結構，
  **前 1116 bytes 跟 libdrm 向量逐 byte 相同**、IT scaling buffer 也相同（`vcn/h264/test_h264.c`，主機端可跑）。
  跟向量不同的地方：decode 結構 Mesa 現行版是 188 bytes（向量是舊版 180），所以 avc 在 0xf4（向量 0xec）；
  decode 欄位改用 Mesa 的值（dpb／ctx 大小、db_pitch、array mode 3、mif_wrc_en 1，field mode 0）。這些差異對不對要上機才知道。
- `vcnctl decodetest --ourmsg`：同一段 libdrm bitstream、同一個 session，只把 decode message 換成自己產生的 → 總和還是 0x020345d8 就代表
  message 格式可用（A/B 對照）。
- `vcnctl decodefile --in <檔>`：解檔案的第一張 IDR。vcn_quadrants.h264 的預期：四象限 Y 約 48／200、UV 約 128（mechrevo vcn/README.md）。
- 還沒做：P／B 畫面需要的 POC 計算與 DPB 管理（sliding window、MMCO）。
