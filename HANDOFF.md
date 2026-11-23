# 交接報告：Framework 13 AMD 黑蘋果（macOS Tahoe）＋ CachyOS 雙系統

更新時間：2026-11-21 16:40（台北時間）
上一份交接：2026-11-19 凌晨（本文件取代它）

## 0. 給接手的 Claude
- 一律用**繁體中文**回覆。不知道就說「不知道」，不要編造；陳述事實要附出處。
- 理性務實，不諂媚；避免「首先、其次、最後」。資訊不清楚先問。給指令前先簡短說明邏輯。
- **CachyOS 必須隨時能正常開機**（使用者每天上課用）。改開機設定前一定先備份、說明還原方式。
- 使用者自己執行 sudo（**絕不要使用使用者的密碼**，對話中曾不小心出現過，已建議他更換）。
- **使用者的操作習慣（很重要）**：
  - 會把你訊息裡的指令「由上往下全部執行」，包括「還原用」的指令 → 一次只給一個要執行的指令；還原指令放在「出問題才用」的段落並寫清楚「現在不要執行」。
  - 從 app 對話框送出的指令每次都開新終端機分頁、工作目錄是 `~` → 一律給**絕對路徑**。
  - ESP 掛上後會被系統很快自動卸載 → 掛載和執行腳本合成一行：
    `sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash <腳本>'`
  - 你的工具看到的 `/tmp` 跟使用者終端機不同，讀 ESP 請用 `/private/tmp/int`。
  - 說「重開了」時先用 `uptime` 確認真的重開過。
- 每個修改 OpenCore 的動作：先備份 → 在副本上模擬 → 給 diff → 給 CachyOS 還原指令。
- 工作檔案都在 `~/fw13-hackintosh/`（本文件所在資料夾）；config 備份在 `~/EFI-backup/`。

## 0c. 參考專案盤點（2026-11-23）
- 5 個參考 repo（mechrevo-f7bsc、ryzenstatus-utils、gem12、660m-Metal、780m-hackintosh）和 nullarc 上游 PR #14/#20/#24/#25 的可用之處整理在 [REFERENCES-1123.md](REFERENCES-1123.md)。
- **2026-11-24 實測**：`GRBM_STATUS` = `0x0000302c`（CP 閒置）→ FW13 **沒有**上游 B-34 的 CP busy 問題，`nullarc-port/patches/mesboot-idle-pr14.patch` 不用裝。
- 同時讀到 GFX 時鐘閘控整個沒開（`0xEC48 = 0x000607ff`、`0xEC49/0xECC5 = 0x0001003c`）。上游開閘控量到閒置約省 1.5–2 W（nullarc `9f37791`）。下一個實驗：`sudo bash /Users/kaoru/fw13-hackintosh/gpu/gpucg-test.sh`（失敗自動寫回；手動還原 `--restore`；重開機也會恢復）。
- **閘控實驗（2026-11-24 04:53）**：開啟後 GPU 正常，閒置封裝 **9.95 → 7.91 W（約 −2 W）**（`gpu/gpucg-1124-045239.txt`）。目前只在執行期開著，重開機就沒了；長時間穩定性待觀察，之後再決定要不要加進 phxboot 開機自動套用。
- 使用一段時間看起來正常（使用者 2026-11-24 回報；螢幕關閉／闔上是否測過未確認）。開機自動套用：`sudo bash /Users/kaoru/fw13-hackintosh/gpu/gpucg-install.sh`（把 `gpu/gpucg.sh` 裝到 `/Users/Shared/gpu/`，phxboot.sh 備份為 `.bak-gpucg`；停用 `touch /Users/Shared/gpu/gpucg-off`）。
- **已安裝（2026-11-24 05:0x）**：重開機後 `/var/log/phxboot.log` 有 `[port] gpucg: 0xEC48=0x00060041 0xEC49=0x0000363f …`、`done 05:06:19`，暫存器值跟實驗時一樣。螢幕關閉→喚醒已測過正常（執行期開著時）；闔上螢幕再打開正常（2026-11-24，開機自動套用後）；長時間使用還沒驗證。
- **閒置功耗重量（2026-11-24 05:11–05:17，`power/idle-measure.sh`，結果檔 `power/idle-1124-051107.txt` 在使用者 Mac 上）**：插電、電池 100%、開機 7 分鐘、GPU 接管＋閘控開、GFXCLK 800 MHz。暖機後 60 筆：**平均 8.17 W、中位數 8.03 W**、最小 7.94 W、最大 9.65 W；C0 約 147‰；TC0P 47 → 44°C。有兩段約 15 秒的 9.5 W 突波（05:13:55–05:14:05、05:15:01–05:15:06），結束時 CPU 前幾名都接近 0%，來源沒查到。對照：11-21/22 插電閒置約 10.3–11 W、gpucg 實驗基準 9.95 W → 閘控後穩定約 8.0 W；CachyOS 插電約 5.5 W，還差約 2.5 W。
- `vcn/PHASE3.md` 的路線 D「不可行」要更正：ryzenstatus-utils 的文件寫 `/System/Library/Video/Plug-Ins` 的解碼器不檢查簽章（FW13 沒驗證）。

## 0a. 最新狀態速覽（2026-11-21 22:50）
- **功耗（閒置封裝，接著充電器，Power Gadget 關、Claude 縮到 Dock）**：GPU 接管開啟 **約 11 W**（下午是 14 W；原本 33 W）。GPU 接管關閉（CPU 繪製）約 6.8 W。CachyOS 約 5.5 W（插電）；用電池時整機約 9.2 W、封裝約 6.4 W（2026-11-22，Discord 開著）。
  - 33 → 14 W：phxboot 開機時送 SMU 指令，GFX 限 800、FCLK 限 1400 MHz（§9b「開機自動套用」；停用：建立 `/Users/Shared/gpu/phxboot-noclk`）。
  - 14 → 11 W：boot-arg `fchxhcimode=1`，FCHXHCIFix 改成只在 USB 有事件時才轉送（kernel_task 30% → 7.5%；文末 FCHXHCIFix 段）。
  - 剩下的差距：nullarc 接管 GPU 本身約 4 W（推測沒有 GFXOFF）。
  - **重量（2026-11-21 22:53，760M 拓撲 + all_apps + Wi-Fi/藍牙開著，接著充電器、電池 100%）**：封裝 10.8–12.7 W，**平均約 11.0 W**（跟之前一樣，Wi-Fi/藍牙/拓撲/all_apps 沒有增加閒置功耗），C0 11–12%，CPU 溫度 TC0P 從 52°C 降到 47.5°C。top：kernel_task 7.7%、airportd 1.5%、WindowServer 1.1%。同一次開機 Power Gadget 開著時（22:50）封裝 20.7 W、63°C。
  - **量功耗前先確認 GPU 狀態**：`/Users/Shared/gpu/phxboot-off` 不存在，且 `/var/log/phxboot.log` 最後一段有 `done`。19:54 曾卡住、自動建立 phxboot-off，原因不明（文末「更正」段）。
- **2026-11-21 新增**（參考機械革命無界 14 Pro 和同方 7840HS 的 EFI）：
  - 音效（VoodooHDA [43]）、Wi-Fi（AirportMtkWlan [44]）、藍牙（BlueToolFixup [11] + SimpleMtkBtFw [45] + 自己編的 SimpleMtkBtPatcher 1.1.0-lefix [46]）、觸控板 VoodooI2CHID 補丁（只換 binary）。
  - **760M 拓撲修好**（CachyOS 實測：8 CU、cu_bitmap 0x3c/0x33、RB 遮罩 0x5，跟 HP 760M 不同）：ESP 上的 PhxBringup = v0.4.0 release 改拓撲表 10 bytes（`gpu/topology-patch.py`）；系統上的 libvulkan_radeon.dylib = v0.4.0 改 canned phoenix 4 bytes 並 ad-hoc 重簽（`gpu/mesa-topology-patch.py`）。RADV 印出 num_cu 8、RB 0x5，mtlprobe 4096/4096。
  - **一般 App 也用 GPU（all_apps）**：phxboot.sh 已改成開機寫 all_apps 清單（擋 mediaanalysisd/photoanalysisd/Spotlight）；Safari 與 WebKit.GPU 確認載入 RADV，使用者回報順暢、沒有新的當機報告。
  - 各段細節在文末。
- **HiDPI（縮放）沒修好**，卡在根本問題：WindowServer 會向 PhxFB 驗證一串 scaled 模式，PhxFB 只接受原生 2256×1504，其他全部拒絕 → 縮放解析度需要 framebuffer 硬體縮放（或複製時縮放）。另外系統從不讀 PhxFB 的合成 EDID，override 檔只採用了名稱（「Framework 13」）。目前裝的是 hidpi2 版 PhxAccel（主動 connect probe、回答 HLDDCSense、模式加 HiDPI 旗標；sha `f7ebf28f…`），無害但沒效果。詳見文末「HiDPI 第二輪」。暫代方案：系統設定 → 輔助使用 → 顯示 → 文字大小。
- Kernel.Add 目前：[39] AMDRyzenCPUPowerManagement、[40] SMCAMDProcessor 啟用（監看用）；[41] AMDPMProbe 啟用；**[42] AMDCState 停用**（兩者都註冊 pmKextRegister，不能同時開；boot-args 的 `amdcst=3` 目前沒作用）。
- boot-args：`-v keepsyms=1 debug=0x100 revpatch=cpuname,sbvmm ipc_control_port_options=0 -vi2c-force-polling amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta phxdebug=1 amdcst=3 fchxhcimode=1 -smbtlefix`
- **備份一覽**：
  - ESP config：`config.plist.bak-1121j`（加 `-smbtlefix` 之前）← 1121i（藍牙前）← 1121h（Wi-Fi 前）← 1121g（fchxhcimode 前）← 1121f（VoodooHDA 前）。`config.plist.nophx` 是舊的救援用 config，**沒有**今天加的東西。
  - ESP kext 原版：`EFI/OC/VoodooI2CHID.kext.orig-1121k`、`EFI/OC/SimpleMtkBtPatcher.kext.v110`、`EFI/OC/PhxBringup.kext.v040`。
  - 系統：`/Users/Shared/gpu/libvulkan_radeon.dylib.v040`（還原：`sudo bash gpu/mesa-topology-install.sh --restore`）、`/Users/Shared/gpu/phxboot.sh.bak-allapps`、`/Users/Shared/gpu/display-overrides.bak-1121`、`phxaccel-port/backup/PhxAccel-hidpi1.kext`（還原：`sudo bash phxaccel-port/hidpi2-restore.sh`）。
- **待辦（依優先）**：
  1. 觀察觸控板補丁效果：每次開機看 `ioreg -r -c VoodooI2CHIDDevice -l -w0 | grep FW13`；失效時先不要重開，跑 `tools/tpad-capture.sh bad`。若補丁無效，下一個實驗是上游 VoodooI2CHID #82（surface/button switch）。
  2. 用電池時的整機功耗還沒量。
  3. HiDPI：先在 PhxFB 加追蹤，查 AppleBacklightDisplay 建立時為什麼沒走 DDC；真正的縮放要做 DCN plane scaler 或複製時縮放（大工程）。
  4. 剩下約 4 W（GPU 接管）：只送 GFXOFF(0x19) 沒效果（2026-11-21 實測）；要省電得研究 RLC power gating，或解碼 SMU EnabledFeatures。
- 查 log：zsh 的 `log` 是內建指令，要用 `/usr/bin/log show …`。腳本裡 `$變數` 後面緊接全形字要寫成 `${變數}`（sudo 的 C 語系會把全形字吃進變數名）。
- GitHub：https://github.com/Kaoru0312/fw13-hackintosh 。每一步更新本文件 → commit → 使用者執行 `git -C /Users/kaoru/fw13-hackintosh push`。

## 0b. 里程碑：目前功能狀態（2026-11-21 22:50 台北時間）
只列實際驗證過的；沒測過的標「沒驗證」。

**✅ 正常可用**
- 開機：macOS Tahoe 26.6 和 CachyOS 雙系統（systemd-boot → OpenCore，選單等 3 秒）。
- 畫面：原生 2256×1504，GPU 負責畫面合成（PhxAMDFB + WindowServer Metal）。系統資訊顯示 **AMD Radeon 760M**、VRAM 4 GB。
- **一般 App 用 GPU**（all_apps；760M 拓撲已修正）：使用者回報順暢，Safari 確認走 GPU。
- 鍵盤正常。亮度鍵可以用；音量鍵可以調音量。
- 音效：喇叭有聲音、內建麥克風可以錄到清楚人聲（VoodooHDA 3.7.1 + ALC295）。開機後預設輸出維持上次選的 Speaker。耳機孔使用者用不到，不測。
- Wi-Fi：AirportMtkWlan 2.0.0（RZ616，介面 en4）。下載約 58–133 Mbps、上傳約 63 Mbps、ping 平均 4–10 ms。
- 藍牙：iPhone（傳統藍牙）配對成功；羅技 MX Master 3S（BLE）可以連，**重開機後會自動重連**。BLE 需要 `-smbtlefix`。
- 觸控板：多指手勢可以用（偶爾開機失效，已裝補丁觀察中，見下方）。
- 外接 USB：羅技 USB 接收器可用（`fchxhcimode=1` 下沒有回報延遲）。
- 電池：電量和充電狀態正常顯示（SMCBatteryManager + ECEnabler）。
- CPU 溫度、頻率、功耗監看：AMD Power Gadget（AMDRyzenCPUPowerManagement + SMCAMDProcessor）。注意：它開著時圖表一直重畫，閒置功耗會被拉高很多，量功耗時要關掉。
- 閒置封裝功耗約 11 W（GPU 接管開啟；見 0a）。
- 上網、Chrome（YouTube 能播）。
- **Safari 播 YouTube 可以了**（2026-11-21 使用者確認；all_apps 之後 Safari 的 WebKit.GPU 走 GPU）。
- 終端機、git、Command Line Tools、Claude app。
- 自動登入。
- 依時間變化的動態桌布（推論可用，沒實測）。

**⚠️ 能用但有限制**
- 觸控板偶爾開機後完全沒反應，重開機就好。2026-11-21 裝了 VoodooI2CHID 補丁（RESET 後補 SET_POWER(ON)），效果待觀察。
- GPU 接管偶爾可能初始化卡住（19:54 發生過一次，原因不明），phxboot 會自動建立 phxboot-off 退回 CPU 繪製，要手動移除並重開兩次。
- 只有原生解析度 2256×1504，**沒有縮放／HiDPI 選項**（PhxFB 不支援硬體縮放；見 0a）。
- 沒有硬體影片解碼，影片全靠 CPU。

**❌ 不能用**
- 睡眠（已經停用，S3 醒不來）。
- 空拍影片桌布（太耗電，等有 GPU 解碼再說）。

**❓ 還沒驗證**
- USB 隨身碟、外接螢幕和 HDMI。
- 視訊鏡頭、指紋辨識。
- AirDrop、接力、AirPods 等藍牙音訊。
- 760M 拓撲 + all_apps 之後、開著 Wi-Fi + 藍牙、用電池時的功耗。

## 1. 硬體
| 項目 | 內容 |
|---|---|
| 機型 | Framework Laptop 13 AMD，32 GB RAM |
| CPU | Ryzen 5 7640U（Phoenix，Zen 4，family 19h） |
| 內顯 | Radeon 760M，PCI **1002:15bf rev cb**，子系統 **f111:0006** |
| 面板 | 2256×1504，13.5" 3:2（約 285×190 mm，201 PPI），無 EDID（macOS 看到的 ID 是 `unkn` 0x756e6b6e / 0x717） |
| 音效 | AZAL（1022:15e3）+ Realtek 晶片（型號未查） |
| Wi-Fi/藍牙 | RZ616，macOS 不支援 |
| BIOS | **iGPU Memory = Gaming（4 GB）**（2026-11-19 改；Auto 是 512 MB） |

## 2. 磁碟與開機流程
- 內建碟：ESP disk0s1（FAT32，CachyOS 掛 `/boot`）、CachyOS btrfs disk0s2、APFS disk0s3（macOS 26.6 25G72）。
- 開機：韌體 → systemd-boot → 「macOS (OpenCore)」→ OpenCore（REL 1.0.8，Timeout 3）→ macOS。CachyOS 直接從 systemd-boot 開，**不經過 OpenCore**。
- CachyOS 已備份到外接碟（使用者自述）。

## 3. 目前狀態總覽（2026-11-21 00:45 驗證）
| 項目 | 狀態 |
|---|---|
| 觸控板 | ✅ boot-arg `-vi2c-force-polling` 解決卡頓（必須保留） |
| 時區、自動更新關閉、減少動態效果/透明度 | ✅ |
| 睡眠 | 完全關閉：`pmset -a sleep 0 standby 0 powernap 0 proximitywake 0 disablesleep 1`（備份 `~/pmset-backup-1119.txt`）。S3 不能用，收包包前要關機 |
| 電池顯示 | ✅ SMCBatteryManager + ECEnabler 1.0.6 |
| GPU（nullarc 移植版） | ✅ GPU 初始化、Metal、**WindowServer 由 GPU 合成**（`--windowserver`），畫面較順，WindowServer 閒置 CPU ~1% |
| 其他 App 用 GPU | ❌ 只開放 WindowServer + 測試工具（拓撲尚未修正） |
| Safari YouTube | ❌ 播不了（推測 Safari GPU 程序不在允許清單，未驗證）；Chrome 可以 |
| 音訊 | ✅ 喇叭有聲音（VoodooHDA_BL [43]，IOPCIPrimaryMatch 0x15e31022，2026-11-21）；內建麥克風可用；耳機孔不需要 |
| HiDPI | ❌ 試了多種方法都沒出現（見 §6） |
| 風扇 | ❌ 閒置約 20 W，進行中（見 §5） |
| Wi-Fi / 藍牙 | ✅ Wi-Fi（AirportMtkWlan [44]，2026-11-21）／✅ 藍牙（SimpleMtkBtFw [45] + patcher 1.1.0-lefix [46]，BLE 滑鼠可用）|

## 4. OpenCore config 重點（ESP `EFI/OC/config.plist`）
- boot-args：`-v keepsyms=1 debug=0x100 revpatch=cpuname,sbvmm ipc_control_port_options=0 -vi2c-force-polling amfi=0x80 amfi_get_out_of_my_way=0x1 -amfipassbeta phxdebug=1`
- csr-active-config 7F080000，SecureBootModel Disabled。
- Kernel.Add 重要項目（編號固定，腳本會檢查）：
  - [0] Lilu、[5] VirtualSMC、[19] SMCBatteryManager（啟用）
  - [37] **PhxBringup**（啟用；release v0.4.0 二進位，Info.plist 的 IOPCIMatch 加了 `0x15bf1002`）
  - [38] ECEnabler（啟用）
  - [39] AMDRyzenCPUPowerManagement、[40] SMCAMDProcessor（**停用**：可讀溫度/頻率/功耗，但不省電，且第一次跟 GPU 接管一起用時黑屏卡死）
  - VoodooHDA_BL.kext 檔案在 Kexts/ 但**不在 config 裡**（已移除）
- ACPI.Add [11] SSDT-ALSOFF.aml（嘗試隱藏 ECS2，**沒有效果**，無害）
- ESP 上的 config 備份：`config.plist.bak-1119c/d/e/f/g/h/i`、`config.plist.nophx`（救援用）
  - `bak-1119i` = 目前使用中的 config（加 VoodooHDA 之前，已還原成這份）
  - **`config.plist.nophx`** = 目前 config 但 PhxBringup 停用 + boot-arg `-phxfboff` → GPU 完全不碰，回到 CPU 繪製
- `OpenCore.efi.release-bak` = RELEASE 版備份（目前用的就是 RELEASE）；DEBUG 1.0.8 在 `~/fw13-hackintosh/oc/dbg/`（`oc-debug.sh` / `oc-release.sh` 可切換，DEBUG 版才會記錄 kext 注入過程）

### 救援指令（CachyOS 下，ESP 在 /boot）
```
sudo cp /boot/EFI/OC/config.plist.nophx /boot/EFI/OC/config.plist     # macOS 進不去時（停用 GPU 路徑）
sudo cp /boot/EFI/OC/VoodooI2CHID-Info.plist.orig /boot/EFI/OC/Kexts/VoodooI2CHID.kext/Contents/Info.plist   # 觸控板壞掉時
```

## 5. 風扇／耗電（進行中，最新一步）
- AMD Power Gadget 量到：閒置約 **20 W**、平均 2.8 GHz、~71 °C（正常應只有幾 W）。
- `powermetrics` 中斷：**I2CD/SMC 約 4180 次/秒、I2CA 約 1985 次/秒**，kernel_task ~35% → CPU 無法進深度睡眠。
- 原因：VoodooI2CHID 對「從沒回報過多點觸控」的 I2C HID 裝置**永遠每 5 ms 輪詢**（`VoodooI2CHIDDevice.cpp` simulateInterrupt）。三個裝置：TPAD（PIXA3854，觸控板，I2CD）、ECSH（FRMW0004，飛航/多媒體鍵，I2CA）、ECS2（FRMW0005，環境光感測器，I2CA）。
- **剛做的修改（2026-11-21 00:40，需驗證）**：ESP 上 `Kexts/VoodooI2CHID.kext/Contents/Info.plist` 的 `VoodooI2CHIDDevice` personality 比對條件從 `IOPropertyMatch {compatible=PNP0C50}` 改成 **`IOPropertyMatch {IOName=PIXA3854}`**，讓 VoodooI2CHID 只接管觸控板。
  - 第一版用 `IONameMatch PIXA3854` 失敗（比對到節點名 TPAD），連觸控板都沒了，已還原後改第二版。
  - 第二版開機後 `ioreg -r -c VoodooI2CHIDDevice` 顯示 **1 個裝置**，再次重開（2026-11-21 14:26）確認只有 TPAD 帶 `IOPropertyMatch {IOName=PIXA3854}`，ECSH/ECS2 沒有 HID 驅動 → 不再被輪詢。量測（`pm2.txt`）：**I2CA 中斷完全消失**（原 ~1985/s），I2CD 2989/s（原 ~4180/s），kernel_task 296 ms/s（原 ~340）。量測時 WindowServer 363 ms/s，可能不是閒置狀態，需在閒置時再量一次。觸控板使用者未明確回報（看來可用）。
  - 下一步：確認觸控板可用 → 請使用者跑 `sudo powermetrics -i 5000 -n 1 --samplers interrupts,tasks -o ~/fw13-hackintosh/pm2.txt`，比較 I2CA 中斷是否消失、kernel_task 是否下降。
  - 備份：ESP `EFI/OC/VoodooI2CHID-Info.plist.orig`、本機 `i2c/VoodooI2CHID-Info.plist.orig`；腳本 `i2c/tpad-only.sh`。
- 使用者回報：觸控板正常，風扇「有比較安靜但還是蠻大聲」。保留此修改。
- 已實驗 `i2c/no-polling.sh`（拿掉 `-vi2c-force-polling`，備份 `config.plist.bak-1121a`）：**更糟** → I2CD 4875/s + GPIO 258/s（輪詢模式是 2989/s），風扇更大聲。**已還原 bak-1121a（2026-11-21 14:40，boot-args 又有 `-vi2c-force-polling`；VoodooI2CHID 只接管 PIXA3854 的修改仍保留）**，需重開機生效。
- WindowServer 取樣（`ws-sample2.txt`，2026-11-21 14:50）：主執行緒忙約 22%（726/3321），時間分散在 QuartzCore、libobjc、libvulkan_radeon（RADV）、NVMTLDriver → 是**正常合成畫面的成本**，不是卡住或空轉。量測當下畫面每秒約 33 幀（Claude app 在更新畫面）；真正閒置時約 1–3 幀/秒、WindowServer ~1%。Metal→Vulkan 轉譯層讓每一幀的 CPU 成本偏高。結論：WindowServer 負載主要來自畫面上有東西在動；不用 Claude app 時關掉可降負載。
- 風扇剩下的主因推測是 macOS 沒有 AMD CPU 電源管理（閒置 ~20 W）。AMDRyzenCPUPowerManagement 在 Zen 4 上不省電且與 GPU 接管一起用時黑屏。這部分目前沒有好方法。
- **建議下一個實驗**：既然 EC 裝置已不被 VoodooI2C 接管，可試著從 boot-args 拿掉 `-vi2c-force-polling`，讓觸控板改回 GPIO 中斷（閒置時幾乎沒有中斷）。風險是當初的游標卡頓可能回來；可逆（把參數加回去即可）。
- 觸控板本身（I2CD ~4180/s）仍會輪詢；要降需改 VoodooI2CHID 原始碼（需完整 Xcode 才能編 xcodeproj，目前只有 CLT）。
- SSDT 隱藏 ECS2 失敗：DSDT 可能已定義 `_STA`，需要真正的 DSDT 才能寫安全的 `_STA→XSTA` 改名。macOS Tahoe 的 ioreg 已不提供 ACPI 表 → 要在 CachyOS 匯出（見 §8）。

## 6. HiDPI（已暫停，狀態穩定）
- 覆寫檔：`/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-756e6b6e/DisplayProductID-717`（含 scale-resolutions 1128×752、1280×853 HiDPI，物理尺寸 285×190 mm）；另有 `DisplayVendorID-1a57/DisplayProductID-1`（給合成 EDID 用，目前沒被用到）。`/Library/Preferences/com.apple.windowserver.plist DisplayResolutionEnabled = true`。都無害，可留。
- **目前裝的 PhxAccel 是原始碼編譯的修改版**（`~/fw13-hackintosh/phxaccel-port/`，改動都標 `[port]`）：NMXAccel 與 PhxFB 都比對 15bf；發布 IOFBScalerInfo + IOFBTimingRange；模式 1 回報詳細時序；實作 validateDetailedTiming/setDetailedTimings（傳入的是 204 bytes 的 IOFBDisplayModeDescription，不是文件說的 V2）；合成 EDID（getDDCBlock）。多次開機穩定、無 panic。
- 結果：系統只驗證標準縮放清單（1280×720…1920×1200、2256×1268、原生），從不呼叫 setDetailedTimings，也從不讀 EDID（`PhxEDIDReads` 不存在）。HiDPI 沒出現。
- 診斷屬性（ioreg PhxAMDFB）：`PhxHiDPIValidateCalls`、`PhxHiDPIRequests`、`PhxHiDPIDetailedCalls`、`PhxHiDPICurrentMode`。
- 教訓：**不要修改已經 setProperty 進 registry 的 OSCollection**（曾因此 panic：`Trying to change a collection in the registry`）。
- 還原成 release 版 PhxAccel：`sudo bash ~/fw13-hackintosh/phxaccel-port/hidpi-restore.sh`（備份在 `phxaccel-port/backup/`）。
- 暫代方案：系統設定 → 輔助使用 → 顯示 → 文字大小。

## 7. nullarc GPU 移植細節
- 專案：github.com/luuumi-dev/nullarc v0.4.0-alpha（參考機 Firebat U6C，780M 1002:1900）。release 二進位只比對 1900；原始碼 HEAD 已含 15bf。
- 安裝包：`~/fw13-hackintosh/nullarc-pkg/`（release + 修改）。已安裝到系統：`/Users/Shared/gpu/`（phxboot、firmware、mesboot）、LaunchDaemon `local.phxboot`、`/Library/Extensions/PhxAccel.kext`（目前是 §6 的修改版）、Metal plugin `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU`。
- 必要修改（Firebat 寫死的值改成執行時讀 PhxBringup 的 `phx-fb-phys`/`phx-fb-size`）：
  - `mesboot.c`：FB_PA（Firebat 0x6A0000000 → 本機 **0x7A0000000**，4 GB 設定下）、系統視窗上限、預設頁、L2 錯誤預設頁（原本指向系統 RAM）。原始碼 `nullarc-port/mesboot.c`。
  - `bringup5.sh`：SETUP_TMR 系統實體位址 = fb_phys + 0x8000000（照 Linux `psp_prep_tmr_cmd_buf`）。
  - `phxboot.sh`：允許清單改成只給 WindowServer（armed）+ 測試工具（拓撲修好前）。
- 驗證：17 個韌體 PSP 載入成功、compute/gfx 佇列測試正確、`nullarc-test/mtlprobe` compute 4096/4096、render 正確。
- 著色器轉譯每個新變體約 6–7 秒（CPU），快取會存到磁碟，之後命中。
- 保護：`sudo touch /Users/Shared/gpu/phxboot-off` 關 GPU（重開生效）；上次開機沒完成時 phxboot 會自動建立此檔。恢復要 `sudo rm` 該檔並**重開兩次**（第一次設定、第二次接管）。
- **拓撲未修**：PhxBringup 把 15bf 當 780M（12 CU），實際 760M 是 8 CU。修法：在 `src/amd/phx_topology.h` 加 f111:0006 的項目，用 MacKernelSDK 重編 PhxBringup（`nullarc-kext/`，路徑有空格要用無空格 symlink）。需要真實 CU/RB 遮罩（見 §8）。

## 8. 等使用者進 CachyOS 時要跑的（fish 語法，唯讀）
```
sudo mkdir -p /boot/fw13-acpi; and sudo sh -c 'cp /sys/firmware/acpi/tables/DSDT /sys/firmware/acpi/tables/SSDT* /boot/fw13-acpi/'; and ls /boot/fw13-acpi
curl -LO https://raw.githubusercontent.com/luuumi-dev/nullarc/main/tools/linux-profile/collect.c; and cc -std=c11 -Wall -Wextra -Werror (pkg-config --cflags libdrm) collect.c -o collect; and ./collect /dev/dri/renderD128 > ~/fw13-760m.json 2> ~/fw13-ip.txt; and sudo cp ~/fw13-760m.json ~/fw13-ip.txt /boot/
```
拿到後：用 `~/fw13-hackintosh/acpi/iasl` 反組譯 DSDT → 寫 ECS2/ECSH `_STA` 改名修補；用 JSON 修 760M 拓撲 → 開放所有 App（含 Safari）用 GPU。

## 9. 待辦（建議順序）
1. **確認觸控板在第二版 VoodooI2CHID 比對下正常**，量 powermetrics 看中斷/耗電改善。
2. 使用者進 CachyOS 時跑 §8 → DSDT 修補、760M 拓撲 → 開放 `all_apps`（照原版擋 mediaanalysisd/photoanalysisd/Spotlight）→ 驗證 Safari YouTube。
3. 音訊：建議 USB-C 音效卡（VoodooHDA 3.7.1-alpha 失敗：OpenCore 注入成功但開機時沒比對；手動載入因 IOAudioStream 類別跟系統 IOAudioFamily 重複而失敗）。
   - **新線索（2026-11-21，branch `audio/voodoohda-pcimatch`）**：機械革命無界 14 Pro EFI（github.com/bbbbrt/mechrevo-wujie14pro-7840hs-780m-hackintosh-efi）用的 `VoodooHDA_BL` 二進位 SHA-256 跟我們 `audio/dl/x/` 的**完全相同**，音效控制器同樣是 AZAL 1022:15e3，作者記錄在 26.7.3 可以出聲（codec 不同：他們是 CX8070）。差別在 Info.plist：我們原檔用 `IONameMatch=HDAS`，FW13 的節點叫 AZAL → 推測就是「沒比對」的原因（未驗證）；他們用 `IOPCIPrimaryMatch=0x15e31022`，而且沒加 OSBundleRequired。
   - 腳本 `audio/voodoohda-pcimatch.sh`：從 dl/x 重新複製 kext（清掉 voodoohda-root.sh 加的 OSBundleRequired=Root）→ 只把比對條件改成 PCI ID → config 裡有 VoodooHDA_BL 就設 Enabled，沒有就加在 Kernel.Add 最後。備份 `config.plist.bak-1121f`。已在假 ESP 上 dry run（`DRYRUN=1 ESP=…`）驗證兩種情境。
   - 執行：`sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/audio/voodoohda-pcimatch.sh'`
   - 開機後看：`ioreg -r -c VoodooHDADevice -d 1 | head -20`、系統設定 → 聲音。CachyOS 還原：`sudo cp /boot/EFI/OC/config.plist.bak-1121f /boot/EFI/OC/config.plist`
   - **已執行（2026-11-21 20:10 開機，[43] VoodooHDA_BL）**：比對成功。ioreg `AZAL@0,6 → VoodooHDADevice`（IOPCIPrimaryMatch 0x15e31022）；系統 IOAudioFamily 740.1 同時正常載入，**沒有類別重複**。codec 是 **Realtek ALC295**。system_profiler 出現三個裝置：Speaker (Analog)、Headphones (Black Right)（目前預設輸出）、Microphone (Digital)（預設輸入）。實際有沒有聲音：待使用者測試。
   - **喇叭有聲音（2026-11-21 20:1x 使用者確認）**。開機後預設輸出是「Headphones」，沒插耳機會聽不到 → 要在系統設定 → 聲音 → 輸出選 Speaker，或用 `audio/setout.swift`（`swiftc -O audio/setout.swift -o /tmp/setout && /tmp/setout Speaker`，會列出所有裝置並把預設輸出切到名稱含該字串的裝置）。
   - **內建麥克風可用（2026-11-21 20:49）**：輸入裝置「Realtek ALC295: Microphone (Digital)」，48 kHz 雙聲道。用 `audio/mictest.swift` 錄 6 秒：RMS 約 -19 到 -25 dB、峰值接近 0 dB（輸入音量 50 時偏大聲，快要破音），回放時使用者確認是**清楚的人聲**。偏大聲的話到系統設定 → 聲音 → 輸入把音量調低。用法：`swiftc -O audio/mictest.swift -o /tmp/mictest && /tmp/mictest 6 /tmp/mic.caf && afplay /tmp/mic.caf`（第一次會跳麥克風權限視窗）。
   - 音量鍵可以調音量（2026-11-21 使用者確認）。
   - 還沒做：喇叭音量是否偏小（偏小可試 Boost=2）。耳機孔：使用者用不到，不測（2026-11-21）。閒置功耗：已確認 VoodooHDA 不會增加。
   - 重開機後預設輸出會維持上次選的 Speaker（2026-11-21 20:40 開機後確認）。
   - 如果比對到了但仍是 IOAudioStream 類別重複，下一步參考他們 Info.plist 的 `OSBundleCompatibleVersion=1.0`、Boost=2、四個 Fix 開關（一次改一個）。
4. HiDPI：暫停。若再試，方向是查 WindowServer/CoreDisplay 怎麼決定 HiDPI（內建面板可能走 ACPI `_DDC` 或 AppleBacklightDisplay 屬性，而非 DDC）。
5. Wi-Fi / 藍牙：USB 硬體。

## 9b. 自製 AMD 電源管理 kext（使用者想自己寫，2026-11-21 提出，尚未開始）
推測的耗電原因（未驗證）：
- macOS 沒有 AMD 的 pmDispatch 電源管理 → XNU 閒置時只用 HLT（C1），進不了 C6 深度睡眠。
- 沒有作業系統發出頻率要求 → Zen 4 可能一直停在高 P-state / boost。
規劃（分階段，每階段可逆；MSR 設定重開機就消失）：
0. **進度**：階段 0 的 kext 已寫好並編譯：`~/fw13-hackintosh/amdpmprobe/`（AMDPMProbe.cpp、build.sh、install.sh，備份 `config.plist.bak-1121b`）。每個 MSR 讀取都先檢查 CPUID 功能位元（讀不存在的 MSR 會 panic）。結果在 `ioreg -r -c AMDPMProbe -l`：CPPC/PState/HWCR/RAPL 原始值，以及每秒更新的 `PackagePowerMilliWatt`、`APERFperMPERFx1000`。正確的 CPPC MSR：C001_02B0 CAP1、02B1 ENABLE、02B2 CAP2、02B3 REQ、02B4 STATUS（下面第 1 點的編號以此為準）。
   **階段 0 結果（2026-11-21 14:57，GPU 接管中，CPU 85% idle）**：Family 0x19 Model 0x74；**CPPC 支援但未啟用**（CPPCEnable=0、CPPCRequest=0）；CPPC Cap1=0xca8a2c10 → highest 202、nominal 138、lowest-nonlinear 44、lowest 16；PStateDef0/1/2 = **3.5 / 2.2 / 1.6 GHz**（FID*200/DID）；PStateCurLimit 0x20（P0–P2）；PStateCtl=0；PStateStatus 大多是 **2（1.6 GHz）**；HWCR boost 未停用；RAPL ESU=16；**封裝功耗穩定約 33 W**。→ 頻率其實已經在最低檔，耗電主因可能不是 CPU 頻率，而是 **C-state 進不去** 或 **iGPU（nullarc 沒有 GPU 電源管理，可能一直全速）**。已比較：**GPU 關閉時 26–31 W**（CPU 75% idle，畫面改由 CPU 繪製，P-state 在 0/1/2 跳動），GPU 開啟時約 33 W。→ iGPU 只佔一小部分，**基礎耗電約 26 W 跟 GPU 無關**，最可能是 CPU 進不去深度 C-state（macOS 在 AMD 上只用 HLT/C1）。因此階段 2（閒置 C-state）才是主要目標；階段 1（CPPC+EPP）可能只有小幅幫助。量測後已請使用者 `sudo rm /Users/Shared/gpu/phxboot-off` 並重開兩次恢復 GPU。
1. **階段 0（唯讀）**：kext 開機時讀 MSR 寫進 ioreg 屬性，不寫入任何東西。讀：CPPC（C001_02B0 Enable、C001_02B1 Cap1、C001_02B3 Req）、PStateCtl/Status（C001_0062/0063）、PStateDef（C001_0064..6B）、HWCR（C001_0015）、RAPL（C001_0299 單位、C001_029B 封裝能量）。用 RAPL 算真實封裝功耗當基準。
2. **階段 1（頻率）**：啟用 CPPC（寫 C001_02B0=1），在 C001_02B3 設 min/max perf 與 EPP（偏省電），讓硬體自己調頻（類似 Linux amd_pstate=active）。用 RAPL 比較前後功耗。
   **ACPI 表已取得（2026-11-21，CachyOS 匯出）**：原始 .aml 與反組譯 .dsl 在 `~/fw13-hackintosh/acpi/tables-linux/`（DSDT + SSDT1..29）。CPU 的 `_CST` 在 **SSDT5.dsl**（每個 `\_SB.PLTF.Cxxx` 都一樣，第 190 行起）：
   - C1：FFixedHW（class 2、offset 2 → MWAIT/HLT 類），latency 1 µs
   - **C2：SystemIO 讀取 port 0x414**（8-bit），latency 18 µs
   - **C3：SystemIO 讀取 port 0x415**（8-bit），latency 350 µs
   - 另有 `_LPI`、`_CPC`（CPPC 描述）、`_CSD`（C-state 依賴：domain 0、coordination 0xFE、num processors 2）。
   - 階段 2 做法：閒置時對 0x415（或 0x414）做一次 `inb` 讓 CPU 進 C3/C2（Linux `acpi_idle` 的做法）。難點在 macOS 上要接管閒置路徑：需要 `pmKextRegister`/pmDispatch（私有，不在公開 KPI），可能要寫成 Lilu 外掛用 `KernelPatcher::solveSymbol` 解析符號，或參考 SMCAMDProcessor 的 lookup_symbol 作法；pmDispatch 結構依 macOS 版本而異，風險高。
   - 拓撲資料（collect.c → fw13-760m.json）**這次沒有產生**，下次進 CachyOS 要再跑 §8 第二行。
   - ECS2（光感測器）已經因 VoodooI2CHID 只接管觸控板而不再被輪詢，SSDT-ALSOFF 可以不用管。
   **階段 2 實測（2026-11-21 15:3x，GPU 接管開著）**：AMDCState 已安裝在 Kernel.Add[42]，載入正常，沒有 panic。`Enabled=Yes`，Mode 2，port 0x414。
   - C2 進入次數每秒約 1 萬次。
   - 一分鐘內取樣 12 次 PackagePowerMilliWatt，範圍 32.2–33.7 W，平均約 32.9 W。和之前約 33 W 的基準相比**沒有下降**。
   - 推測（未驗證）：讀 port 0x414 可能沒有真的讓核心進入 CC6，要先讀 MSR C001_0073（CstateBaseAddr）確認；也可能耗電大戶不是閒置的核心（WindowServer、GPU、I2C 中斷）。
   - 下一步：在 AMDPMProbe 加讀 C001_0073，再用 `amdcst=3` 比較。
   - 已完成（2026-11-21）：AMDPMProbe 改為加讀 C001_0073（ioreg `CStateBaseAddr`、`CStateIoPort`）和 C001_0296（`CStateConfig`），編譯完成。
     - 安裝：`amdpmprobe/update.sh`，只換 kext；舊版會備份到 ESP 的 `EFI/OC/AMDPMProbe.kext.v1`。
     - CachyOS 還原：`sudo rm -rf /boot/EFI/OC/Kexts/AMDPMProbe.kext && sudo cp -r /boot/EFI/OC/AMDPMProbe.kext.v1 /boot/EFI/OC/Kexts/AMDPMProbe.kext`
     - 判讀：如果 CStateIoPort ≠ 0x414，就是 C2 沒省電的原因。
     - **結果（2026-11-21 15:39，開機正常，無 panic）**：`CStateBaseAddr=0x413`、`CStateConfig=0x484848`。
       - 依 AMD PPR 的欄位定義（我根據記憶判讀，尚未對照原文）：讀 0x413、0x414、0x415 分別對應 CCR0、CCR1、CCR2 三個等級。每個等級的位元組都是 0x48，bit6（CC6EN）= 1，代表三個等級都允許進入 CC6。
       - 所以 `inb(0x414)` 用的 port 是對的，port 錯誤這個假設排除。
       - 功耗仍然約 33 W，問題比較可能是核心太忙，閒置的時間太少。
     - 下一步：用 MPERF 除以 TSC 量 C0 佔用率（MPERF 只在 C0 時計數），確認核心有多少時間真的在閒置。
     - 已完成編譯（2026-11-21）：probe 第 3 版。
       - ioreg 新增 `C0PermilleCPU<APIC ID>`、`C0PermilleAvg`（千分比）和 `C0CPUsSeen`。
       - 計時器在哪顆 CPU 上跑就量哪顆，所以 CPU 會陸續出現。
       - 讀值時用 pushf/cli 關中斷，不需要新的核心符號。
       - 安裝一樣用 `update.sh`。還原備份 `EFI/OC/AMDPMProbe.kext.v1` 是第 1 版（沒有 C-state 讀取），不會被覆蓋。
       - 第 2 版的原始碼保留在 `amdpmprobe/AMDPMProbe.cpp.v2`。
     - **第 3 版結果（2026-11-21 15:44，開機約 2 分鐘，GPU 接管開著，無 panic）**：
       - 量到 8 顆 CPU，C0 佔用率 207–424‰，平均 292‰（約 29%），封裝功耗約 33.2 W。
       - 也就是核心約 7 成時間在閒置，功耗卻仍約 33 W，所以耗電大戶**不是**核心忙碌，比較可能是 GPU（PhxAccel／WindowServer 合成）或 SoC 其他部分（記憶體控制器、Data Fabric）。這是推論，未驗證。
       - 下一步：用 `phxboot-off` 關 GPU 接管，量同樣的 C0 和功耗做比較；再看能不能讀 GPU 的功耗。
       - 同一次開機觸控板又失效了，但 ioreg 顯示 VoodooI2CHIDDevice（PIXA3854）和 PrecisionTouchpadHIDEventDriver 都有載入。原因未查。
     - **用電池驗證 RAPL（2026-11-21 16:01，拔掉充電器，GPU 接管開著）**：
       - 電池讀數：16.17 V × 1.98 A ≈ **32 W 整機放電**。ioreg 的 Amperage 是無號 64 位元，要減掉 2^64 才是負值的放電電流。前 50 秒 InstantAmperage 停在舊值，沒有更新。
       - AvgTimeToEmpty = 88 分鐘，也就是約 1.5 小時就會把電用完。
       - 同時段 probe：封裝功耗 **19.3–20 W**，C0 平均只有 **4–5%**。
       - 封裝 20 W 小於整機 32 W，數字合理，所以 **RAPL 讀數可信，耗電是真的**。
       - 核心幾乎全在閒置，封裝仍有 20 W。推論（未驗證）：SoC 沒有進入封裝層級的低功耗，可能是 iGPU 沒有 GFXOFF／電源閘控（nullarc 沒有 GPU 電源管理），或是 Data Fabric／記憶體一直維持高時脈。
       - 下一步：到 CachyOS 量閒置時的封裝和整機功耗當硬體基準，順便看 amdgpu 的 gfxoff 狀態。
     - **CachyOS 基準量測（待做）**：腳本在 `tools/cachyos-baseline.sh`，只讀不改設定。
       - 量 60 秒的 RAPL 封裝功耗、電池整機功耗、amdgpu 功耗、gfxoff 狀態，以及 C-state、EPP、top。
       - 結果寫到 `/boot/fw13-baseline.txt`，macOS 可以從 ESP 讀到。
       - 用法見文末「CachyOS 下次要做」。
     - **CachyOS 基準結果（2026-11-21 16:09，原始輸出在 `measurements-cachyos-baseline-1121.txt`）**：
       - 封裝功耗 **5.2–7.5 W，多數約 5.5 W**。同樣閒置，macOS 是約 20 W，**差約 14 W，而且是軟體造成的**。
       - 當時**接著充電器**（狀態 Charging），所以 bat_W 約 13.5 W 是充進電池的功率，不是整機耗電。
       - amdgpu power1 讀數 4–8 W。這可能是 socket 或 SoC 的功耗，定義未確認。
       - gfxoff 狀態讀不到（debugfs 沒有輸出）。
       - cpu0 的閒置時間大部分在 **C3**（163 s），C2 只有 22 s、C1 5 s。
       - cpufreq 是 amd-pstate-epp，EPP 為 balance_performance。
       - → 下一步：讓 macOS 的 AMDCState 改用 C3（`amdcst=3`，腳本 `cstate/c3.sh`，備份 bak-1121d），比較封裝功耗。
     - **CachyOS 基準・用電池（2026-11-22 06:20，原始輸出在 `power/cachyos-baseline-1122.txt`）**：
       - 狀態 Discharging，亮度 28819/65535（約 44%）。**整機（bat_W）9.05–9.37 W，平均約 9.2 W**；封裝 6.18–6.75 W，平均約 6.4 W。
       - 比 11/21 插電時的封裝約 5.5 W 高約 0.9 W，但這次**不是乾淨閒置**：Discord 三個程序合計約 30% CPU、kwin 9%、beam.smp（root）4.5%；EPP 也從 balance_performance 變成 balance_power。差異來源沒有分開量，不能直接比。
       - amdgpu power1 6.04–6.21 W，跟封裝很接近 → 推測這個讀數是整個 SoC（socket）功耗，不是 GPU 本身（未確認）。
       - gfxoff 狀態一樣讀不到（`/sys/kernel/debug/dri/*/amdgpu_gfxoff_status` 沒有輸出）。
       - cpu0 開機以來的閒置時間：C3 342.7 s（約 77%）、C2 95.7 s（約 21%）、C1 7.4 s。
       - 電池：`charge_full` 3,186,000 µAh、`charge_full_design` 3,572,000 µAh、`voltage_min_design` 15.4 V → 目前滿電約 **49 Wh**（設計約 55 Wh，健康度約 89%）。文末「闔上螢幕用電池」寫的 61 Wh 不對。
       - 估算：CachyOS 閒置約 9.2 W → 約 **5.3 小時**；macOS 約 21 W → 約 **2.3 小時**。
     - **C3 結果（2026-11-21 16:16–16:19，amdcst=3，接著充電器，GPU 接管開著，無 panic）**：
       - Mode 3，port 0x415，C3 每秒約 8,000 次。C0 從 78% 一路降到 10%。
       - 封裝功耗**仍然 32.2–33.6 W**，和 C2 一樣。
       - 結論：核心的 C-state 不是瓶頸。C2 或 C3 都一樣，核心睡得再好也省不到電。
       - 附帶觀察：同樣閒置，接著充電器約 33 W，用電池時約 20 W。可能是 EC／平台在 AC 和電池下的功耗設定不同，原因未確認。
       - 目前保留 amdcst=3。要回到 C2，就還原 bak-1121d。
     - **新方向：SMU 時脈／GFXOFF**。
       - Linux 是由 amdgpu 透過 SMU（MP1 mailbox）管理 GFX、FCLK、SOCCLK 的 DPM 和 GFXOFF；macOS 上沒有人做這件事。
       - nullarc 的 `phxctl` 可以送 SMU 訊息：`phxctl smuinfo`、`phxctl smu <msg> [arg]`，需要 root 和 phxdebug=1。可送的訊息見 nullarc-src `PhxNativeABI.h`。
       - 先只讀：smuinfo、GetGfxclkFrequency 0x17、GetFclkFrequency 0x18。
       - 之後可以試 SetSoftMaxGfxClk 0x1B、SetSoftMaxFclkByFreq 0x1E 限制時脈（重開機就恢復）。
       - **AllowGfxOff 0x19 有風險**：nullarc 文件記錄 GFXOFF 允許時 CP 的 PFP 會卡住，可能讓 WindowServer 的 GPU 合成卡死。
     - **SMU 查詢結果（2026-11-21 16:20，閒置）**：
       - PMFW 0x004c6000（76.96.0），DriverIf 8。
       - EnabledFeatures lo 0xfbfff7ff、hi 0x07a5f3f3。對照 Linux 的 `drivers/gpu/drm/amd/pm/swsmu/inc/pmfw_if/smu_v13_0_4_pmfw.h`（torvalds/linux master，2026-11-21 下載）解碼：
         - **沒開的只有**：CSTATE_BOOST、GFX_TEMP_VMIN、FUSE_PG、GFX_DEM、PERF_LIMIT、CORE_DLDO、FASTBYPASS_CLDO、VDDOFF_ECO、ZSTATES_ECO、DS_UMCCLK。
         - **都已開啟**：GFX_DPM、FCLK_DPM、SOCCLK_DPM、DS_GFXCLK、DS_FCLK、DF_CSTATES、DF_LIGHT_CSTATE、CC6、ZSTATES、S0I3、CPPC、ATHUB_PG。
         - 意思是 SMU 的 DPM 和省電功能本身都開著，GFXCLK 會卡在 2600 MHz 是「被要求」的。可能原因（未驗證）：GPU 一直有工作（WindowServer 的著色器轉譯），或 nullarc 不允許 GFXOFF，讓 GFX 一直維持上電。
         - 16:45 在 Claude app 開著的情況下用 top 取樣：kernel_task 31%（I2C polling，約 711 irq/s）、WindowServer 31%、Claude app 約 20%，封裝約 19.6 W。所以量閒置功耗時，Claude app 本身也會把數字拉高。
         - **WindowServer 取樣（16:50，5 秒，閒置，檔案 ws-sample3.txt 沒進 repo）**：堆疊頂端幾乎全是等待（mach_msg、workq、cvwait、semaphore_timedwait）。實際在跑的樣本只有約 200 筆，最多的是 longcopy 48 筆、NVMTL 的 nvmtl_snapshot_set_md 12 筆、CoreAnimation 的 prepare_layer。換算下來閒置時 CPU 用量只有約百分之幾，**沒有看到之前那種著色器轉譯（libnvmtl_translate）**，fc 快取應該已經熱了。
           - 所以 top 看到的 31% 是畫面在更新時（例如 Claude app 在動）才出現的，不是閒置負擔。「GPU 閒置也被 WindowServer 佔滿」這個假設偏弱。
         - DS_UMCCLK（記憶體控制器時脈深度睡眠）沒開，可能是剩下差距的一小部分；Linux 上是否有開未確認。
       - **GFXCLK 2600 MHz，閒置時卡在最高檔**；FCLK 1600 MHz。
     - **限制 GFXCLK 上限 800 MHz**（`phxctl smu 0x1B 800`，回讀 0x17 = 800，重開機就失效）：
       - 封裝功耗從約 33 W 降到 **15–22 W，多數約 20 W**（接著充電器，C0 13–18%）。
       - 確認 GPU 時脈是主要耗電來源之一。畫面目前沒有異常回報。
     - GFXCLK 再往下壓：0x1C 和 0x1B 都送 400 MHz，回讀仍然是 800 MHz，所以 **800 MHz 是實際下限**。
     - **FCLK 上限設 800 MHz**（`phxctl smu 0x1E 800`）：回讀 **1400 MHz**（0x578），推測 1400 是目前允許的下限，原因未確認。
       - 和 GFX 800 MHz 一起套用後，封裝功耗從約 24 W 一路降到 **約 13 W**（16:24，C0 10%，接著充電器）。
       - 畫面沒有異常回報。
       - 下降一部分可能是系統慢慢穩定下來造成的，要再量久一點才能確認。
     - **SOCCLK 上限 400 MHz**（0x1D 400，回 OK，沒辦法回讀）：
       - 畫面正常。封裝功耗穩定後約 13.5–15.4 W，和沒設時（13.6–14.6 W）**沒有差別**。前 30 秒的 24 W 是使用者在操作。
       - 結論：SOCCLK 不是剩下那約 8 W 的來源，**不加入開機自動套用**，重開機就恢復預設。
     - **開機自動套用**：`clk/install.sh` 會在 `/Users/Shared/gpu/phxboot.sh` 的 `rm -f "$MARK"` 前面插入兩個 SMU 指令，0x1B 800 和 0x1E 800。
       - 備份：`phxboot.sh.bak-clk`。
       - 開關檔：`/Users/Shared/gpu/phxboot-noclk`，建立它就跳過時脈設定。
       - 結果寫在 `/var/log/phxboot.log`，會有一行 `[port] clocks: gfx … fclk …`。
       - repo 裡的 `nullarc-pkg/gpu/phxboot.sh` 已經同步成修改後的版本。
       - **已安裝並驗證（2026-11-21 16:28 開機）**：phxboot 在 16:29:44 送出時脈設定（gfx 0x320 = 800、fclk 0x578 = 1400），沒有 panic。
         - 封裝功耗：設定前（開機後前 90 秒）約 33 W，設定後**約 13.6–14.6 W**（接著充電器，C0 8–19%）。
         - phxboot 在 M2 路徑會先觀察 WindowServer 90 秒才收尾，所以開機後前約 1.5 分鐘仍是高功耗。
     - 編譯用的 SDK 連結改成 `~/.mksdk` → `~/fw13-hackintosh/MacKernelSDK`。scratchpad 重開機會被清空，所以不再用。
   **階段 2 kext 已寫好並編譯（2026-11-21）**：`~/fw13-hackintosh/cstate/`（AMDCState.cpp、install.sh，備份 `config.plist.bak-1121c`）。用 `pmKextRegister(102, …)` 註冊只有 `MachineIdle` 的 pmDispatch；閒置時 `inb(0x414)`（C2）。boot-arg `amdcst=0` 關、`2` C2（預設）、`3` C3（0x415）。ioreg `AMDCState` 有 `Enabled`、`IdleEntriesC2/C3`。依據：xnu `osfmk/i386/pmCPU.c`（machine_idle 無 pmDispatch 時只 sti;hlt；版本不符會 panic；重複註冊會 panic → AMDRyzenCPUPowerManagement 必須維持停用）；ARAT=1。Info.plist 依賴 `com.apple.kpi.private` —— 若 OpenCore/核心不准第三方連結就會載入失敗（不會 panic），那時要改成 Lilu 外掛解析 `_pmKextRegister`。
3. **階段 2（閒置 C-state）**：註冊 pmDispatch 的 idle 回呼，照 ACPI `_CST`（Zen 通常是 System IO port 讀取進 C2/C3）進深度睡眠。風險最高（可能 hang/panic），需要 DSDT/SSDT 找 `_CST` 的 port。
- 建置：MacKernelSDK + CLT（已備，見 nullarc-kext/phxbringup/build.sh 的寫法），由 OpenCore 注入（Kernel.Add 加在最後，避免改動既有編號），kext 內用 inline asm rdmsr/wrmsr。
- 參考：trulyspinach/SMCAMDProcessor 原始碼（pmDispatch hook 寫法、RAPL 讀法）；Linux `drivers/cpufreq/amd-pstate.c`、`drivers/acpi/processor_idle.c`。
- 注意：AMDRyzenCPUPowerManagement 與 GPU 接管同時使用曾黑屏，階段 2 特別要小心；每次測試前確認 `config.plist.nophx` 救援可用。

## 10. 踩過的坑
- VoodooI2C `IONameMatch` 比對的是節點名（TPAD），不是 ACPI ID → 用 `IOPropertyMatch {IOName=...}`。
- `phxboot` 偵測到上次沒完成會建 `phxboot-off`，GPU 就不會啟動。
- zsh 會把 `$N:A` 當修飾語；腳本用 bash、變數一律 `${VAR}`（sudo 時 C 語系下 `$TAG（` 會吃掉全形字）。
- `log show` / `dmesg` 看不到 PhxAccel 的 IOLog → 改用 ioreg 屬性記錄。
- OpenCore RELEASE 版不記錄 kext 注入；要看就暫時換 DEBUG 版。
- 軟體更新：已關自動更新；安裝命令列工具要用 `softwareupdate -i "Command Line Tools for Xcode 26.6-26.6"` 並先建 `/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress`。已裝好（clang 21）。
- 舊坑（上一份交接）：外接碟 RTL9210 不穩、CachyOS 預設 fish 無 heredoc、diskutil 對 APFS 的 Physical Store 錯誤等。

## GitHub repo（2026-11-21 建立）
私人 repo：https://github.com/Kaoru0312/fw13-hackintosh（main 分支）。macOS 本機的 `~/fw13-hackintosh` 就是工作副本，GitHub 憑證存在 macOS 鑰匙圈。
- 每做完一步：更新這份 HANDOFF.md，然後 `git -C ~/fw13-hackintosh add -A && git -C ~/fw13-hackintosh commit -m "…" && git -C ~/fw13-hackintosh push`。
- 在 CachyOS 看：瀏覽器登入 GitHub 直接看 HANDOFF.md；或 `git clone https://github.com/Kaoru0312/fw13-hackintosh.git`，密碼欄貼 fine-grained token。
- 絕對不提交含 SMBIOS 序號的 config.plist（`.gitignore` 已排除 `config*.plist*`）。token 不要貼進任何對話或檔案。

## CachyOS 下次要做（2026-11-22 更新）
1. ~~閒置功耗基準~~（2026-11-21 插電量過；2026-11-22 06:20 用電池又量一次：整機約 9.2 W、封裝約 6.4 W，Discord 開著，見「CachyOS 基準・用電池」）。要重量的話：先拔掉充電器、關掉其他程式，開機後閒置 2 分鐘再執行。
   ```
   git clone https://github.com/Kaoru0312/fw13-hackintosh.git ~/fw13-hackintosh   # 第一次；之後用 git -C ~/fw13-hackintosh pull
   sudo bash ~/fw13-hackintosh/tools/cachyos-baseline.sh
   ```
   clone 時密碼欄要貼 GitHub token。也可以不 clone，直接在瀏覽器打開 repo 的 tools/cachyos-baseline.sh，按「Raw」複製內容存成檔案。
   結果在 `/boot/fw13-baseline.txt`，回 macOS 後讓 Claude 讀。
2. ~~760M 拓撲~~（2026-11-21 21:57 已完成，結果在 `gpu-topology/fw13-760m.json`）。
3. ~~確認睡眠模式~~（2026-11-22 已完成：只有 `[s2idle]`，見「睡眠與硬體解碼」段）。

## 觸控板偶爾開機後完全不能動（2026-11-21 開始追）
- 症狀：偶爾開機後觸控板完全沒反應，重開機就好。發生時 ioreg 裡 VoodooI2CHIDDevice（PIXA3854）和 PrecisionTouchpadHIDEventDriver 都在，所以不是驅動沒載入。
- 快照腳本 `tools/tpad-capture.sh`（只讀，要 sudo），存到 `tpad/<時間>-<ok|bad>.txt`。內容包含 kext、ioreg 樹、powermetrics 中斷次數、kernel 日誌、dmesg。
- 做法：能用時先拍一份 ok 當對照；失效時**先不要重開**，馬上拍一份 bad，再比較兩份。
- 正常時的對照：`tpad/1121-163536-ok.txt`，拍攝時開機約 8 分鐘。
  - 完整的驅動樹都在：TPAD → VoodooI2CHIDDevice → PrecisionTouchpadHIDEventDriver → VoodooInput → AppleMultitouchDevice。
  - I2CD 中斷約 **711 次/秒**（之前量過約 2990）。

## 溫度／頻率監看（2026-11-21，使用者要求）
- `amdpm/monitor-on.sh`：啟用 [39] AMDRyzenCPUPowerManagement、[40] SMCAMDProcessor（0.7.2f1，ESP 上本來就有），並**停用 [42] AMDCState**。兩者都會呼叫 `pmKextRegister`，重複註冊會 panic。
- 備份 bak-1121e。CachyOS 還原：`sudo cp /boot/EFI/OC/config.plist.bak-1121e /boot/EFI/OC/config.plist`
- 風險：11/20 第一次和 GPU 接管一起用時曾經黑屏卡死，原因未查。
- 顯示用 App：`amdpm/dl/x/AMD Power Gadget.app`。
- **已套用並驗證（2026-11-21 16:46 開機）**：
  - AMDRyzenCPUPowerManagement 0.7.2 和 SMCAMDProcessor 已載入，AMDCState 沒有載入，沒有 panic。
  - phxboot 正常完成，GPU 接管和時脈限制都有生效，**這次沒有黑屏**。
  - AMD Power Gadget 已複製到 `~/Applications` 並開啟。
  - 開機 2 分鐘時封裝約 20 W（C0 31%，還在開機後的忙碌期），之後要再量一次閒置功耗，確認這個 kext 沒有讓功耗變高。

## 動態桌布（2026-11-21 討論，**使用者決定先不做**）
- **依時間變化的動態桌布**（HEIC 裡包多張圖，系統定時切換）：不需要硬體解碼，幾乎不耗電，直接在系統設定裡選就可以用。
- **空拍影片桌布（Aerial，4K HEVC）**：這台在 macOS 沒有硬體影片解碼，nullarc 沒有實作 VCN，所以會改用 CPU 解碼，功耗明顯上升，或者乾脆播不出來。這是推論，未實測。Safari 的 YouTube 失敗可能是同一個原因。
- 之後要做的話有兩條路：
  1. **把影片換成低規格版**（1080p、低 fps、H.264），讓 CPU 解碼負擔變小。系統下載的桌布影片能不能直接替換未確認；或者改用第三方動態桌布 App 播放自己轉好的檔案。要量轉檔前後的功耗。
  2. **自己寫硬體解碼（長期研究，以月計）**：
     - 第 1 層：驅動 VCN 4（PSP 載韌體、ring、解碼指令），可以參考 Linux amdgpu 和 Mesa。
     - 第 2 層：接上 VideoToolbox。這是 Apple 私有、沒有公開文件的外掛介面，要逆向，是真正的難點，幾乎沒有前例（這是判斷，沒有找到來源）。
     - 只做完第 1 層，桌布和 Safari 都用不到。

## 閒置功耗重量（2026-11-21 20:16–20:22，接著充電器、電池已充滿）
目的：確認加了 VoodooHDA [43] 之後閒置功耗有沒有上升。當時載入的是監看 kext（AMDRyzenCPUPowerManagement + SMCAMDProcessor，AMDCState 沒載入；boot-args 雖有 amdcst=3 但不起作用）。時脈限制有生效（gfx 800 / fclk 1400）。
- **AMD Power Gadget 開著**（開機 5 分鐘）：封裝 **22.1–24.9 W，平均約 23 W**，C0 12–17%。`pm4.txt`：WindowServer **約 950–1000 ms/s**（吃滿一個核心）、I2CD 約 8,200/s、kernel_task 約 260–290 ms/s。
- **關掉 AMD Power Gadget、Claude app 縮到 Dock、不碰機器**（等 30 秒後取樣 90 秒）：封裝 **6.8–14.9 W，平均約 9.5 W**，C0 從 11% 降到 5%。top：kernel_task 29%、WindowServer 4.8%。
- 結論：
  - **VoodooHDA 不會增加閒置功耗**：pm4 裡完全沒有 AZAL/HDA 的中斷，coreaudiod 也不在負載排行裡，關掉 Power Gadget 後功耗反而比之前的 14 W 基準還低。
  - **AMD Power Gadget 本身就讓功耗多出約 13 W**：它的圖表一直重畫，讓 WindowServer 吃滿一個核心（Metal→Vulkan 轉譯，每一幀的成本很高）。要量功耗時不要開它；平常也不建議一直開著。可改看 `ioreg -r -c AMDPMProbe -l | grep PackagePowerMilliWatt`。
  - 之前的 14 W 基準可能也被 Claude app 或其他畫面更新拉高了。真正閒置時，最低 6.9 W 已經接近 CachyOS 的 5.5 W。
  - 剩下的主要負擔是 kernel_task 約 29%（I2C 觸控板輪詢）。pm4 的 I2CD 約 8,200/s 明顯高於之前的 711–2,989/s，但量測時使用者有在操作，閒置時的中斷數沒有量。
- 還沒驗證：AMDRyzenCPUPowerManagement 跟 AMDCState 哪個比較省（這次沒拆開比較）；用電池時的整機功耗。

## kernel_task 的真正來源：FCHXHCIFix 每秒 1,000 次轉送（2026-11-21 20:30–20:40，branch `usb/fchxhci-mode`）
- 原本以為 kernel_task（閒置約 29–38%）是觸控板輪詢造成的。實際量測：
  - `pm5.txt`（等 40 秒後取樣 10 秒）：I2CD **713/s**，正好是 VoodooI2CHID 閒置 50 ms 輪詢的量。原始碼（VoodooI2CHIDDevice.cpp simulateInterrupt）：開機後還沒碰過是 5 ms，觸碰後 1.5 秒內是 2 ms + IOSleep(1)，之後是 50 ms。pm4 的 8,200/s 是剛操作過的忙碌狀態。照 VoodooI2C 的 IODelay 估算，閒置輪詢最多約 2% 一顆核心 → **不是主因**。
  - `kstack.txt`（DTrace `profile-997 /pid == 0/` 10 秒，SIP 已關所以可以用）：扣掉 idle 後，最大的是 **AppleUSBXHCI::interruptOccurred → ioInterrupt → ml_io_read**（MMIO 讀取），約 3,500 次取樣 ≈ **0.35 顆核心**，跟 kernel_task 的 CPU 時間吻合。另有不帶符號的位址 0xffffff800f9a69xx 呼叫 IOWorkLoop::signalWorkAvailable，減掉 KASLR slide（0xb800000）後是 **FCHXHCIFix.kext**（載入位址 0xffffff80041a6000，大小 0x9000）。
- FCHXHCIFix 1.0.2（com.carrizored，config 裡啟用）：ioreg `FCHXHCIFix-state` = "1 sources, 1338001 forwards, 1338001 polls …; running, **mode 2 (every poll)**"，量到 **1,000 forwards/s**。
  - 反組譯（`otool -tV`）：boot-arg `-fchxhcioff` 關閉；`fchxhcimode` 沒設或為 0 時預設 **2**。輪詢執行緒每次 `IOSleep(1)`；讀 USBSTS，**EINT（0x8）有設 → 寫回清除並轉送**；沒設 → 只有 mode ≥ 2 才轉送。
  - 所以 mode 2 等於每 1 ms 叫 AppleUSBXHCIPCI 把整個控制器狀態讀一遍，非常耗 CPU。
- **下一個實驗**：boot-args 加 `fchxhcimode=1`（腳本 `usb/fchxhci-mode1.sh`，備份 `config.plist.bak-1121g`，已在假 ESP dry run）。預期 kernel_task 大幅下降、閒置功耗再降。風險：如果這台的 EINT 不可靠，外接 USB 鍵鼠可能又會延遲（內建鍵盤和觸控板不受影響）。CachyOS 還原：`sudo cp /boot/EFI/OC/config.plist.bak-1121g /boot/EFI/OC/config.plist`
- 附帶：Claude app 停在前景（尤其終端機在跑指令）時，WindowServer 約 1,000 ms/s、封裝約 23 W；縮到 Dock 時 WindowServer 只有約 5%。量測時要縮到 Dock。
- **已執行並驗證（2026-11-21 20:40 開機）**：`fchxhcimode=1` 生效，`FCHXHCIFix-state` 顯示 "running, mode 1 (on EINT)"，**forwards 約 47/s**（polls 仍是 1,000/s）。
  - 閒置量測（開機後等 75 秒，取樣 90 秒，Claude app 縮到 Dock，接著充電器）：封裝 **6.1–7.4 W，平均約 6.8 W**（原本約 9.5 W），C0 約 9%。**kernel_task 7.5%**（原本 29–38%）、WindowServer 3.9%。已經很接近 CachyOS 的 5.5 W。
  - 當時 AMD Power Gadget 有在執行（登入時自動開啟，PID 694），但視窗沒有顯示時看起來不會拉高功耗。
  - 待驗證：外接 USB 鍵盤/滑鼠有沒有延遲、USB 隨身碟傳輸速度。

## Wi-Fi：AirportMtkWlan（2026-11-21，branch `wifi/airportmtk`）
- 參考 kevin8717/TongFang-7840HS-Hackintosh（7840HS + MT7921，macOS 26.7.2 / Darwin 25.6.0）。他們用 **AirportMtkWlan 2.0.0**（上游 Arxusion/AirportMtkWlan，GPL-2.0），本地改了 4 處：beacon 有效位、teardown/deep-sleep 順序、15 秒背景掃描節流、`lastWclScanMs`。2.4/5 GHz 可用。
- 它的 IOPCIMatch `0x796114c3 0x060814c3 0x792214c3 0x061614c3` **包含 FW13 的 RZ616（ioreg `pci14c3,616`）**。連結的是系統內建 IO80211Family / IOSkywalkFamily / corecapture，他們的 config 沒有額外的 kernel patch 或 Block。另有 RZ616 專用分支 lincyppq/AirportMtkWlan-RZ616（還沒看）。
- kext 放在 `wifi/dl/AirportMtkWlan.kext`（不進 repo），binary SHA-256 `2d6fc08b…af383c`。
- 腳本 `wifi/airportmtk.sh`：加在 Kernel.Add 最後（預計 [44]），MinKernel 25.0.0 / MaxKernel 25.99.99，備份 `config.plist.bak-1121h`。已在假 ESP（bak-1121g 的複本）dry run。
- 執行：`sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/wifi/airportmtk.sh'`
- CachyOS 還原：`sudo cp /boot/EFI/OC/config.plist.bak-1121h /boot/EFI/OC/config.plist`
- 藍牙（之後做）：laobamac SimpleMtkBtFw 1.1.0 內含 `BT_RAM_CODE_MT7922_1_1_hdr.bin`，但比對清單只有 0e8d:0608、0e8d:3802、04ca:3563；FW13 藍牙是 **0e8d:e616**（USB「Wireless_Device」），要在 Info.plist 加 personality，另外需要 BlueToolFixup + SimpleMtkBtPatcher。
- 同一份 repo 其他可參考的：VoodooI2CHID 補丁「RESET 後補 SET_POWER(ON)」（可能跟觸控板偶爾開機失效有關，原始碼 kevin8717/VoodooI2C-htix5288）；VoodooGPIO spurious IRQ 遮罩修正；nerux-real/nullarc-760M（760M 分支，跟拓撲問題有關）。
- **已執行並驗證（2026-11-21 20:56 開機）**：`com.flxxxxddd.AirportMtkWlan (2.0.0)` 載入，沒有 panic。Wi-Fi 介面是 **en4**（en0 仍是 NullEthernet），使用者用系統 UI 連上網路，拿到 192.168.0.229，預設路由走 en4。
  - 實測：ping 1.1.1.1 ×10 平均 10.4 ms（3.9–18.6）、0% 掉包；Cloudflare 下載 50 MB **約 58 Mbps**、上傳 20 MB **約 63 Mbps**（只測一次，路由器和距離未記錄）。
  - `networksetup -getairportnetwork en4` 會顯示「not associated」，這類驅動常見，不代表沒連上。
  - 還沒驗證：閒置功耗有沒有因為 Wi-Fi 上升（量測當下封裝 20 W 是在跑速度測試）、重開機後會不會自動連線、5 GHz/2.4 GHz 是哪一個、AirDrop/接力（推測不行）。

## 藍牙：SimpleMtkBtFw（2026-11-21，branch `bt/mtk`）
- FW13 藍牙：USB **0e8d:e616**「Wireless_Device」，**bDeviceClass 239 / SubClass 2 / Protocol 1**（複合裝置，底下有 BT_ACL_If、BT_SCO_If、BT_ISO_If，目前由 AppleUSBHostCompositeDevice 接管）。
- SimpleMtkBtFw 1.1.0（laobamac，GPL-3.0）內含 MT7922 韌體，韌體檔名依晶片 ID 決定，跟 USB product ID 無關。但它的 personality 沒有 e616，通用那條要求 bDeviceClass 224 → 比對不到。
- 腳本 `bt/mtk-bt.sh`：
  - kext 從 kevin8717/TongFang-7840HS-Hackintosh（6758dda）複製到 `bt/dl/`（不進 repo），腳本會檢查三個 binary 的 SHA-256。
  - BlueToolFixup 換成 2.7.2，config 裡原本停用的 **[11] 改成 Enabled**（MinKernel 21.0.0 不動）。
  - SimpleMtkBtFw（ESP 上的 Info.plist 加 personality `SimpleMtkBtFw_MT7922_0e8d_e616`，idVendor 3725、idProduct 58902、IOProbeScore 94000）→ **[45]**；SimpleMtkBtPatcher（Lilu 外掛）→ **[46]**。
  - 備份 `config.plist.bak-1121i`。已在假 ESP 上依序跑 Wi-Fi + 藍牙腳本 dry run，編號跟實機一致。
  - 注意：macOS 的 /bin/bash 是 3.2，腳本不能用關聯陣列（第一版用了，已改）。
- 執行：`sudo sh -c 'mkdir -p /tmp/int; diskutil mount -mountPoint /tmp/int disk0s1; bash /Users/kaoru/fw13-hackintosh/bt/mtk-bt.sh'`
- CachyOS 還原：`sudo cp /boot/EFI/OC/config.plist.bak-1121i /boot/EFI/OC/config.plist`
- **已執行並驗證（2026-11-21 21:03 開機）**：BlueToolFixup 2.7.2、SimpleMtkBtFw 1.1.0、SimpleMtkBtPatcher 1.1.0 都有載入，沒有 panic。
  - SimpleMtkBtFw 接管 0e8d:e616（IOProbeScore 顯示 99000），`fw_name = BT_RAM_CODE_MT7922_1_1_hdr.bin`。
  - system_profiler：Bluetooth Controller **State: On**、Chipset THIRD_PARTY_DONGLE、Firmware v9489 c6166、Transport USB，支援 HFP/A2DP/HID/LEA 等服務。
  - Wi-Fi 同時正常：開機 1 分鐘時 ping 5 次掉 1 次（最高 245 ms，系統還在忙）；開機 2 分鐘後 ping 30 次 **0% 掉包、平均 4.5 ms**，下載約 **133 Mbps**。
  - 還沒驗證：實際配對（耳機、滑鼠、鍵盤）、藍牙開著時的閒置功耗、睡眠相關不適用（睡眠已停用）。
- **羅技 MX Master 3S（BLE 滑鼠）配對失敗（2026-11-21 21:03–21:07）**：
  - 掃描得到（DvF Central Connectable、Aprc Mouse、BLE、BTv 5.1、廣播 HID 服務 UUID 0x1812）。滑鼠出現兩個位址：XX:XX:XX:XX:XX:B2（連 30 秒沒連上就取消）、**XX:XX:XX:XX:XX:B3**（推測是不同 Easy-Switch 頻道）。
  - B3：**LE 連線本身成功**（Outgoing LE Connection complete status 0、GATT connected），但同一毫秒內 `encryptionStatusChangedCb status=4803 isPairing=0`、`TS_LE_EncryptionCompleteCb completed with error STATUS 4803`，加密沒有建立 → 約 8 秒後系統設定以 "Unused" 斷線，之後出現 "Device does not have _HID_SERVICE_"（GATT 服務沒探索完）。另一次斷線 reason 722。
  - 20 分鐘內 4803 出現 13 次，每次嘗試都一樣 → 不是偶發。推測（未驗證）：MT7922 韌體或 SimpleMtkBtPatcher 對 LE 加密/SMP 的處理有問題，或 macOS 對 THIRD_PARTY_DONGLE 的 LE 配對流程不相容。TongFang 的文件只說藍牙可用，沒提 BLE 滑鼠/鍵盤。
  - 查 log 的注意事項：zsh 的 `log` 是內建指令，要用 `/usr/bin/log show …`。
  - 下一步：(1) 確認是 BLE 專屬問題還是全部配對都壞 → 試一個傳統藍牙裝置（耳機、手機）；(2) 查 SimpleMtkBtPatcher 的上游 issue / 原始碼（laobamac/SimpleMtkBtFw）有沒有 LE 配對相關的修正；(3) MX Master 3S 可改用 Logi Bolt 接收器（本機現在插的是 046d:c534 Unifying/nano 接收器，3S 不支援 Unifying）。
- **傳統藍牙配對正常（2026-11-21 21:10）**：iPhone 13 Pro 配對成功（`Pairing Completed … result 0`、`Classic SMP pairing completed … status 0`，連結金鑰已存）→ 問題只在 **BLE**。
- **找到上游同一個問題**：flxxxxddd/SimpleMtkBtFw（我們用的 1.1.0 就是這個 fork 的 release）issue **#2**「[Tahoe] MT7922/RZ616 BLE HID pairing stalls waiting for PHY / Data Length events」：RZ616（0489:E0D8）+ Tahoe 26 + 羅技 K251 BLE 鍵盤，LE 連線成功，但 bluetoothd 卡在 `wait-for-phy` → `LE_READY_WAIT_FOR_LENGTH`，因為 MT7922 不會送 LE PHY Update Complete，`LE Set Data Length (0x2022)` 回 Command Complete 成功但不送 Data Length Change。我們的 log 也有 `ready-state: LE_READY_WAIT_FOR_PHY`，症狀相符。
  - 修正：**PR #3**（iussch/SimpleMtkBtFw 分支 `tahoe-mt7922-ble-fix`，e1f9781，SimpleMtkBtPatcher.cpp +661 行，**尚未合併、沒有編好的 release**）。開機參數 `-smbtlefix` 才啟用：攔截 `IOUSBHostIOSource::io`，在 Remote Features Complete 之後注入假的 PHY Update Complete，送一次真的 0x2022，再把它的 Command Complete 改寫成假的 Data Length Change（27 bytes / 328 µs）。作者實測 K251 可以配對，AirPods 修正不受影響。類似 Intel 的 IntelBluetoothFirmware PR #446 / issue #514。
  - 要用的話得自己編 SimpleMtkBtPatcher（需要 Lilu SDK + MacKernelSDK，只有 CLT，要照 amdpmprobe/cstate 的方式手動編）。
  - 現有 patcher 的開機參數（strings）：`-smbtrandaddr`（LE random address 處理，預設關）、`-smbtcompatoff`、`-smbtcompatdbg`、`-smbtcompatbeta`。
- **自己編 PR #3 的 SimpleMtkBtPatcher（2026-11-21，已安裝並驗證）**：
  - 原始碼：`bt/src/SimpleMtkBtFw`（iussch 分支 `tahoe-mt7922-ble-fix`，e1f9781，不進 repo）。看過 diff：新攔截點（`IOUSBHostIOSource::io` 三個多載）只在 `-smbtlefix` 且 Tahoe 時才掛上；只在 Read Remote Features 之後的短暫期間改寫特定格式的 HCI 事件；沒有其他動作。沒有 `-smbtlefix` 時行為同 1.1.0。
  - Lilu SDK：Lilu-1.7.2-DEBUG（跟 ESP 上的 Lilu 1.7.2 一致）。編譯腳本 `bt/build-patcher.sh`（CLT + `~/.mksdk`，仿 cstate/build.sh，自己產生 kmod_info.c，C++ gnu++17）→ `bt/build/SimpleMtkBtPatcher.kext`，版本字串 1.1.0-lefix，binary sha256 `1847ec51a085a0f0…`。
  - 檢查：跟 1.1.0 比，多 import 的只有 `_IOSleep`、`__Znwm`、`__ZdlPv`、`_thread_call_allocate/enter1/free`，都在 /System/Library/Kernels/kernel 找得到。IOUSBHostFamily 在 Tahoe 只存在 KC 裡，沒辦法直接 nm；符號解析失敗時 Lilu 只會記 "failed to resolve"，不會 panic。`kextlibs` 在 Tahoe 上新舊版都回報 "No libraries found"，不能當判斷依據。
  - 安裝腳本 `bt/patcher-lefix.sh`：ESP 上的 1.1.0 先備份成 `EFI/OC/SimpleMtkBtPatcher.kext.v110`，原地換 binary（[46] 不動），boot-args 加 `-smbtlefix`，備份 `config.plist.bak-1121j`。已在假 ESP（依序跑 Wi-Fi、藍牙腳本 + 目前的 boot-args）dry run。
  - 開機後檢查：`ioreg -r -c IOResources -l -w0 | grep -o '"SimpleMtkBtLE[A-Za-z]*" = [0-9]*'`（PhyFakeCount / SetDataLengthSentCount / DataLengthFakeCount 配對時會增加）。
- **已安裝並驗證（2026-11-21 21:17 開機）**：boot-args 有 `-smbtlefix`，patcher 載入（kextstat 仍顯示 1.1.0，因為 CFBundleVersion 沒改，只改了 ShortVersionString）。**MX Master 3S 配對成功並連上**（system_profiler：Connected、Vendor 0x046D、Product 0xB034、Firmware RBM22.01_0006、BLE）。Wi-Fi 同時正常（en4 有 IP）。
  - IOResources 計數：`SimpleMtkBtLEPhyFakeCount = 1`、`SimpleMtkBtLESetDataLengthSentCount = 1`、`SimpleMtkBtLESetDataLengthLastIOReturn = 0`、**`SimpleMtkBtLEDataLengthFakeCount = 0`**。也就是假 PHY 事件和私有 0x2022 都送了，但「把 Command Complete 改寫成 Data Length Change」那一步沒有發生，配對還是成功了。推測（未驗證）：這台的 MT7922 韌體在送 0x2022 之後有自己發出 Data Length Change，或 Tahoe 在這個情況下沒有等它。關鍵修正可能只是假 PHY 事件。
  - 還沒驗證：重開機後滑鼠會不會自動重連、長時間使用的穩定性（游標延遲、斷線）、BLE 鍵盤、AirPods 等音訊裝置。

## 觸控板：VoodooI2CHID RESET 後補 SET_POWER(ON)（2026-11-21，branch `i2c/hid-reset`）
- 目標：觸控板偶爾開機後完全沒反應（驅動樹都在）。
- 參考 kevin8717/VoodooI2C-htix5288（TongFang 用的 fork）。那個 fork 大部分是 HTIX5288 專用的 GPIO 診斷，不適合直接用；只取兩點（都是 Linux i2c-hid 的行為）：(1) RESET 完成後再送一次 SET_POWER(ON)；(2) RESET 逾時不再 `return kIOReturnTimeout`，繼續往下。
- 底版：**VoodooI2C 2.9.1 內附的 VoodooI2CHID（a478fd6）**，跟現在 ESP 上的原版同一份原始碼，只多這個補丁（`i2c/patches/hid-reset-power-on.patch`）。沒有帶上游 master 的 #77/#81/#82（#82 = surface/button switch，若這次無效可以當下一個實驗）。
- 補丁另外在 VoodooI2CHIDDevice 上發布 ioreg 屬性：`FW13PostResetPowerOn`（次數）、`FW13PostResetPowerOnRet`、`FW13ResetTimeouts`。失效時拍 bad 快照可以一起比對。
- 編譯：`i2c/build-hid.sh`（原始碼在 `i2c/src/`，不進 repo：VoodooI2C v2.9.1 + VoodooGPIO 733dc80 + VoodooI2CHID a478fd6）→ `i2c/build/VoodooI2CHID`，sha256 `dc57d2ed…`。
  - **注意**：一定要 `-mmacosx-version-min=10.12`。用專案設定的 10.11 時，MacKernelSDK 的 IOHIDEventService.h 會選舊版面配置，slot 7–13 變成 `_RESERVED`，跟系統的 IOHIDEventService（copyEvent、dispatchEvent…）對不上。改 10.12 後跟原版只差 slot 14（原版 RESERVED14，新版 dispatchBiometricEvent，同一個位置）和多一個 `IOService::newUserClient` 多載。
- 安裝：`i2c/hid-reset-patch.sh` 只換 `Contents/MacOS/VoodooI2CHID`（會先確認 ESP 上是 2.9.1 原版 sha `65975f70…`），Info.plist 和 config.plist 都不動，整個 kext 先備份成 `EFI/OC/VoodooI2CHID.kext.orig-1121k`。已在假 ESP dry run。
- CachyOS 還原：`sudo rm -rf /boot/EFI/OC/Kexts/VoodooI2CHID.kext && sudo cp -r /boot/EFI/OC/VoodooI2CHID.kext.orig-1121k /boot/EFI/OC/Kexts/VoodooI2CHID.kext`
- 驗證方式：因為是偶發，要多開機幾次觀察；每次開機看 `ioreg -r -c VoodooI2CHIDDevice -l -w0 | grep FW13`。
- **已安裝（2026-11-21 21:34 開機，關機清風扇後）**：新 VoodooI2CHID 載入，`FW13PostResetPowerOn = 1`、`FW13PostResetPowerOnRet = 0`（成功），沒有 `FW13ResetTimeouts`（這次 RESET 沒逾時）。PrecisionTouchpadHIDEventDriver active。偶發失效有沒有改善要多開機幾次才知道。

## ⚠️ 更正：GPU 接管從 19:58 起就一直是關的（2026-11-21 21:38 發現）
- `/Users/Shared/gpu/phxboot-off` 建立於 **19:58**。`/var/log/phxboot.log`：19:54 那次開機 phxboot 印出 "PhxAMDFB on the panel: 1" 之後就沒有下文（沒有 compute/gfx 測試、沒有 done），19:58 下一次開機判定 "previous attempt did not finish" → 自動關掉 phxboot 和 PhxAMDFB。之後每次開機都是 "kill switch present: nothing to do"。19:54 為什麼卡住：**不知道**（最後一次成功是 17:04；這段期間的變更沒有紀錄）。
- **影響這次工作階段的所有量測**（20:10 之後）：
  - 畫面全程是 **CPU 繪製**，沒有 GPU 合成；**SMU 時脈限制也沒有套用**（限制是 phxboot 送的）。之前看到的 `[port] clocks` 那行其實是 17:04 的舊紀錄，判讀錯了。
  - 「閒置 9.5 W → fchxhcimode=1 後 6.8 W」是 **GPU 接管關閉** 狀態下的數字，不能直接跟之前「GPU 接管 + 時脈限制 = 14 W」比。fchxhcimode 的改善（kernel_task 30%→7.5%、1000→47 次/秒）是同條件前後比，仍然成立。
  - 推論（未驗證）：沒有 nullarc 接管時，SMU 自己會讓 GPU 進低功耗，所以閒置反而更低；之前 GFXCLK 卡在 2600 MHz 是 nullarc 接管造成的。
  - 「AMD Power Gadget / Claude app 讓 WindowServer 吃滿一個核心」也是 CPU 繪製下的現象，GPU 接管時的情況不同。
  - 音效、Wi-Fi、藍牙、觸控板的結果跟 GPU 無關，不受影響。
- 目前 BIOS iGPU memory 仍是 4 GB（ioreg `phx-fb-size = 4294967296`）。
- 要恢復 GPU：`sudo rm /Users/Shared/gpu/phxboot-off` 然後重開兩次（第一次設定、第二次接管）。風險：19:54 的卡住原因不明，現在又多了 VoodooHDA、AirportMtkWlan、藍牙 kext、AMDRyzenCPUPowerManagement；卡住的話 phxboot 會再自動建立 phxboot-off，最壞情況用 `config.plist.nophx` 救。
- **已恢復 GPU 接管（2026-11-21 21:39–21:43）**：`sudo rm /Users/Shared/gpu/phxboot-off` → 第一次開機 phxboot 完整跑完（compute/gfx 測試通過、armed for next boot、clocks 套用、done 21:39:33）→ 第二次開機 "PhxAMDFB on the panel: 1"、"Metal for WindowServer (armed)"、armed and released 21:41:46、clocks 套用、done 21:43:20。這次沒有卡住（19:54 卡住的原因仍不明）。
  - **GPU 接管 + 時脈限制 + fchxhcimode=1 的閒置功耗**（done 後等 30 秒、取樣 90 秒，Power Gadget 沒開、Claude 縮到 Dock、接著充電器）：封裝 **10.6–12.7 W，平均約 11.0 W**，C0 14–18%。top：kernel_task 7.3%，WindowServer 沒進前 6 名。
  - 比較：GPU 接管 + 時脈限制、FCHXHCIFix mode 2（16:28）約 14 W → 加 fchxhcimode=1 後約 **11 W**；GPU 關閉（CPU 繪製）約 6.8 W。也就是 nullarc 接管 GPU 本身在閒置時約多 4 W（推測是 GFX 沒有 GFXOFF/電源閘控）。

## 760M 拓撲（2026-11-21）
- **這是什麼**：GPU 的「拓撲」是硬體配置表——幾個 shader engine、每個有幾組 shader array、哪些運算單元（CU）和像素輸出單元（RB）是開著的。同一顆晶片出廠時會依良率關掉一部分 CU（780M 開 12 個、760M 開 8 個），**哪幾個被關掉每顆晶片可能不同**，只能從實機讀。Mesa RADV 用這張表決定怎麼分配工作。
- **現狀**：PhxBringup 用 `phx_find_topology()` 依 PCI 子系統 ID 選預設表；只認得 HP 的 760M（103c:8c6a），FW13（1002:15bf rev cb、子系統 f111:0006）落到 **780M 預設（12 CU、RB 遮罩 0xf）**。ioreg 證實：`phx-topology-cu = 12`、`phx-topology-rb = 4`（應該是 8 CU）。所以 phxboot 的 Metal 允許清單只開給 WindowServer + 測試工具（`/Users/Shared/gpu/phxboot.sh` 第 75、96 行的註解：「760M topology 進來後再放回 all_apps」）。
- 已確認 nerux-real/nullarc-760M 分支的 `phx_topology.h` 跟本機 nullarc v0.4.0 原始碼一樣，沒有 FW13 的資料 → 沒有捷徑，要實機資料。
- HP 760M 的預設表可以參考格式：SE 1、SA/SE 2、CU/SH 6、RB 4、RB 遮罩 0xa、cu_bitmap {0xf, 0xf}、8 CU。**不能直接套用**，FW13 的遮罩可能不同。
- 也可以在 macOS 用 `phxctl gc` 讀 CC_GC_SHADER_ARRAY_CONFIG，但這些暫存器要先寫 GRBM_GFX_INDEX 選 SE/SA，GPU 接管中寫它有風險 → 不採用。
- **步驟**：
  1. CachyOS：`sudo bash ~/fw13-hackintosh/tools/cachyos-760m-collect.sh`（先 `git -C ~/fw13-hackintosh pull`）。只發 AMDGPU_INFO ioctl（`tools/collect-760m.c` = nullarc tools/linux-profile/collect.c），結果寫到 `/boot/fw13-760m.json`、`/boot/fw13-ip.txt`、`/boot/fw13-760m-info.txt`。上次（§8）沒產生 JSON，這版會檢查 cc / libdrm 標頭並自動找 amdgpu 的 render node。
  2. macOS：讀 JSON → 在 `phx_topology.h` 加 FW13 項目（比對 subvendor 0xf111 / subdevice 0x0006）→ 用 MacKernelSDK 重編 PhxBringup → 換 ESP 上的 PhxBringup.kext（[37]）。
  3. 開機確認 `phx-topology-cu = 8`、「關於這台 Mac」顯示 760M → phxboot 改成 all_apps（照原版擋 mediaanalysisd/photoanalysisd/Spotlight）→ 測 Safari YouTube、一般 App 的 Metal。
- **實測資料（2026-11-21 21:57，CachyOS 6.18.55-2-cachyos-lts，`gpu-topology/fw13-760m.json`）**：1002:15bf rev 0xcb、子系統 f111:0006；SE 1、SA/SE 2、CU/SH 6、RB 4、**RB 遮罩 0x5**、**8 CU**、**cu_bitmap SA0 = 0x3c、SA1 = 0x33**。跟 HP 760M 預設（RB 0xa、0xf/0xf）**不同**，所以不能套 HP 的表。VBIOS 113-PHXGENERIC-001。
- **做法改成修改 release binary 的資料表，不重編**（branch `gpu/760m-topology`）：
  - ESP 上的 PhxBringup = nullarc v0.4.0 release 原版（sha `4a88035f…`）。repo 裡 `nullarc-kext/` 的原始碼**比 release 新**（不改直接編，跟 release 比多了 IORWLock、deferClient/reapClients、vmFlushTlb、sysMemLocked 等），重編會帶進沒在這台驗證過的改動。
  - FW13 落到 `g_phx_780m_default`，所以只把 binary 裡這張 128 bytes 的表換成實測值：`gpu/topology-patch.py`（檢查 release sha、JSON 通過 phx_topology_valid、780M 表和 HP 表各只出現一次）→ `gpu/build/PhxBringup`，sha `6c947da7…`。實際只改 **10 bytes**，位置 0x6a70 起，在 `__TEXT,__const` 內。release kext 本來就沒有簽章。
  - Mesa（patch 0007）拿到的拓撲直接用來配置；PCI ID 只用來決定顯示名稱（只認 HP 的才叫 "760M Graphics"，其他顯示 "AMD Phoenix captured profile"）。PhxBringup 依 CU 數把 PCI `model` 設成 "AMD Radeon 760M"。
  - 安裝：`gpu/topology-install.sh` 只換 binary（先確認 ESP 上是 v0.4.0 原版），Info.plist（IOPCIMatch 含 0x15bf1002）和 config 都不動，整個 kext 先備份成 `EFI/OC/PhxBringup.kext.v040`。已在假 ESP（用 ESP 上真正的 Info.plist）dry run。
  - CachyOS 還原：`sudo rm -rf /boot/EFI/OC/Kexts/PhxBringup.kext && sudo cp -r /boot/EFI/OC/PhxBringup.kext.v040 /boot/EFI/OC/Kexts/PhxBringup.kext`
  - 開機後確認 `ioreg -r -c PhxBringup -l -w0 | grep phx-topology`（應該 cu = 8），GPU 接管和 phxboot done 都正常後，才進下一步改 phxboot 的 all_apps。
- **已安裝並驗證（2026-11-21 22:07 開機）**：ioreg `phx-topology-cu = 8`（原本 12）、`phx-topology-rb = 4`；system_profiler 顯示 **AMD Radeon 760M**、VRAM 4 GB、Metal Supported。GPU 接管正常（armed and released 22:07:42、clocks 套用、done 22:09:12）。`nullarc-test/mtlprobe`：compute **4096/4096 correct**。
- **但 Mesa 那一半還沒修**：mtlprobe 顯示的裝置名稱仍是 "AMD Radeon 780M Graphics (RADV PHOENIX)"。查了已安裝的 `/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU/nvmtl/libvulkan_radeon.dylib`（= v0.4.0 release，sha 1f2181d1…）：**沒有** mesa-patches-phoenix 的 0007（runtime topology 查詢；有的話名稱會是 "AMD Phoenix captured profile"），所以 RADV 仍用內建的 780M canned 資料（12 CU、RB 遮罩 0xf），不會去問 PhxBringup。
  - 也就是說：kernel 端（PhxBringup）的拓撲已正確，但 Mesa 端還是 780M。推測（未驗證）：RB 遮罩不對（Mesa 以為 4 個 RB 全開，實際只有 RB0、RB2）可能讓 occlusion query 之類等所有 RB 回報的操作卡住，這可能就是 upstream 在拓撲修好前不開 all_apps 的原因。
  - **所以還不能開 all_apps。** 兩條路：(A) 照 PhxBringup 的做法，改 libvulkan_radeon.dylib 裡 canned 的 phoenix 裝置資料（cu_bitmap / enabled_rb_pipes_mask / cu_active_number），改完要 ad-hoc 重新簽章；(B) 套 mesa-patches-phoenix 0001–0007 自己編 Mesa（比較正確但工程大，需要 meson/ninja/mako 等）。
- **Mesa 端改資料表（路線 A，2026-11-21，已安裝並驗證）**：
  - canned "phoenix" 來自 Mesa `src/amd/common/amdgpu_devices.c`（base f5cb8ee）。在已安裝的 dylib 裡找 `drm_amdgpu_info_device` 開頭（device_id 0x15bf、chip_rev 9、external_rev 0xa、pci_rev 4、family 148、SE 1、SA 2、counter 99810、clock 2700000/937000、CU 12、cu_bitmap 0x3f/0x3f、RB 0xf、RB 數 4），只出現一次，offset 0x118db50。
  - `gpu/mesa-topology-patch.py` → `gpu/build/libvulkan_radeon.dylib`：只改 **4 bytes**（cu_active 12→8、cu_bitmap 0x3c/0x33、RB 遮罩 0x5）。原檔 ad-hoc 簽章（identifier `radv-5555494430853611a5f6358ba9589efbabdf75c1`），測過 `codesign -f -s - -i <同 identifier>` 後 `codesign -v` 通過。
  - 安裝：`sudo bash gpu/mesa-topology-install.sh`（檢查原檔 sha `1f2181d1…`、備份到 `/Users/Shared/gpu/libvulkan_radeon.dylib.v040`、簽章後換上）。還原：`sudo bash gpu/mesa-topology-install.sh --restore`。這是系統卷上的檔案，CachyOS 改不到；畫面異常時 phxboot 會自動 phxboot-off 退回 CPU 繪製，登入後再還原。
  - 驗證：重開機後 phxboot done、mtlprobe 4096/4096。之後才考慮 all_apps。
  - 安裝時腳本在最後一行印訊息出錯（`$ID）` 被 sudo 的 C 語系當成變數名 → `ID�: unbound variable`），但替換和簽章已經完成：系統上 dylib 的欄位讀回 CU 8、0x3c/0x33、RB 0x5，跟原檔只差這 4 bytes + 簽章區 31 bytes，`codesign -v` 有效、identifier 不變，備份 sha 正確。已把這次寫的腳本裡所有 `$變數` 緊接全形字的地方改成 `${變數}`（§10 踩過的坑又踩一次）。
  - **驗證（2026-11-21 22:16 開機）**：phxboot 正常（WindowServer armed and released 22:16:52、frames on the panel 1632、clocks 套用、done 22:18:27）。`mtlprobe` 4096/4096 correct。`RADV_DEBUG=info mtlprobe` 印出 **num_cu = 8、cu_mask SA0 = 0x3c / SA1 = 0x33（各 4）、enabled_rb_mask = 0x5、num_rb = 2**、num_se = 1、num_cu_per_sh = 6 → Mesa 端拓撲正確。裝置名稱仍顯示 "AMD Radeon 780M Graphics (RADV PHOENIX)"，那是 patch 0002 寫死的字串，跟拓撲無關。
  - **核心端（PhxBringup）和 Mesa 端都已是 760M 實測拓撲。** 下一步：phxboot 改 all_apps（upstream 寫法：`all_apps "; WindowServer composites…" '!WindowServer'`，擋 mediaanalysisd/photoanalysisd/Spotlight），測 Safari YouTube、一般 App。
- **all_apps 臨時測試（2026-11-21 22:2x）**：手動把 `/Library/GPUBundles/nvmtl-allow.txt` 改成 upstream all_apps 格式（`-mediaanalysisd`、`-photoanalysisd`、`-Spotlight`、`*`、`!WindowServer`；原清單備份 `/Users/Shared/gpu/nvmtl-allow.txt.bak`）。使用者回報「蠻順的」；22:20 之後 DiagnosticReports 沒有新的當機/卡住報告；Safari 和 `com.apple.WebKit.GPU` 都載入了 libvulkan_radeon（真的走 GPU）。Safari YouTube 是否已恢復正常：使用者沒有單獨回報，待確認。
- 寫進開機流程的腳本 `gpu/all-apps.sh`：只換 phxboot.sh 第 76–77 行（M2 路徑寫清單的 printf → `all_apps "…" '!WindowServer'`，以及對應的 echo），備份 `phxboot.sh.bak-allapps`，同步 repo 的 `nullarc-pkg/gpu/phxboot.sh`。已在 phxboot.sh 副本上 dry run，產生的清單跟臨時測試那份相同。**已執行（2026-11-21 22:3x）**：phxboot.sh 第 76–77 行已換掉，備份 `phxboot.sh.bak-allapps`，repo 副本已同步。之後每次開機都是 all_apps。

## HiDPI 第二輪（2026-11-21，branch `display/hidpi`）
- 現況：CoreGraphics 只列出 1 個模式 2256×1504；`CGDisplayScreenSize` = **796×530 mm**（= 2256 px ÷ 72 dpi），所以 macOS 當成低 PPI 螢幕，不提供 HiDPI。AppleBacklightDisplay 的 vendor/product 是 756e6b6e/717（沒有 EDID），override 檔裡的實體尺寸沒被採用。`PhxEDIDReads` 從沒出現 → 第一輪做的合成 EDID 從來沒被讀過。
- 原因（參考 nerux-real/nullarc-760M 的 phxfb.cpp，註解描述的症狀跟我們一樣）：(1) 面板是韌體點亮的，連線從沒「改變」，IOFramebuffer 從不 probe 面板讀 EDID；(2) AppleDisplay 讀 EDID 前會用 NULL value 問 `kConnectionSupportsHLDDCSense`，我們對 idx 0 沒回答；(3) 模式旗標沒有 Native/BuiltIn/ValidForHiRes/AcceleratorBacked，CoreDisplay 不給 scaled 模式。
- 修改 `phxaccel-port/accel/phxfb.cpp` 的 PhxAMDFB（標 `[port] hidpi2`）：
  - 新增 `fConnCall` thread_call + `connFire()`：註冊 connect interrupt 後 500 ms 觸發一次、再 4 s 一次（共 2 次）；ioreg `PhxConnFired` 記次數。start 配置、stop 釋放。
  - `getAttributeForConnection`：idx 0 的 `kConnectionSupportsHLDDCSense` 先回成功（value 可為 NULL）。
  - `getInformationForDisplayMode`：mode 1 加 `kDisplayModeNativeFlag | BuiltInFlag | ValidForHiResFlag | AcceleratorBackedFlag | ValidForMirroringFlag`。
  - 合成 EDID 沿用第一輪（vendor "FRW" = 0x1a57、product 1、285×190 mm）。對應的 override `DisplayVendorID-1a57/DisplayProductID-1` 第一輪就放好了（scale-resolutions 2256×1504 HiDPI → 1128×752、2560×1706 HiDPI → 1280×853）。
- 編譯：`phxaccel-port/build.sh ~/.mksdk` → sha `f7ebf28f…`。
- 安裝：`sudo bash phxaccel-port/hidpi-install.sh`（換 /Library/Extensions/PhxAccel.kext、重建 Aux KC；它保留最早的 backup/PhxAccel.kext）。目前裝的第一輪版本另存 `phxaccel-port/backup/PhxAccel-hidpi1.kext`（sha 3277b0cb…），退回用 `sudo bash phxaccel-port/hidpi2-restore.sh`。
- 預期：開機後 `PhxConnFired` = 2、`PhxEDIDReads` 出現、AppleBacklightDisplay 變成 vendor 0x1a57 / product 1、CGDisplayScreenSize ≈ 285×190 mm、系統設定 → 顯示器出現縮放選項。風險：顯示器身分改變後 WindowServer 的顯示偏好會重設；WindowServer 若反覆當掉，phxboot 會退回 CPU 繪製。
- **已安裝（2026-11-21 22:32 開機）**：all_apps 也同時生效。結果：`PhxConnFired = 2`（log：22:33:27、22:33:31 各一次 "connect interrupt -> PhxAMDFB"），**但 `PhxEDIDReads` 仍沒出現**，AppleBacklightDisplay 還是 756e6b6e/717，CGDisplayScreenSize 仍是 796×530 mm，只有 1 個模式。推測：AppleBacklightDisplay 開機時已經建立（沒有 EDID），connect interrupt 時連線狀態沒變（CheckEnable 一直是 1），IOFramebuffer 不會重建 IODisplay，也就不會讀 EDID。nerux 的情況是一開始根本沒有 display（display id 0）。驅動端再追要反覆改、編、重開，先改走使用者層。
- **改用 override 提供 EDID（已執行 22:40，無效）**：
  - `display/make-edid.py` → `display/fw13-edid.bin`：跟 getDDCBlock 一樣的 128 bytes（FRW/1、285×190 mm、2256×1504 @ 60 Hz、235.70 MHz、checksum OK）。
  - `display/edid-override.sh`：兩份 override（756e6b6e/717 和 1a57/1）都寫入 `IODisplayEDID` + 實體尺寸 + scale-resolutions 4 個（backing 2256×1504→看起來像 1128×752、2560×1706→1280×853、2880×1920→1440×960、3008×2006→1504×1003）。原 Overrides 備份到 `/Users/Shared/gpu/display-overrides.bak-1121`。已在副本 dry run。
  - 列模式工具：`display/modes.swift`（`swiftc -O display/modes.swift -o /tmp/modes && /tmp/modes`）。
- **override 結果（2026-11-21 22:40 開機）**：system_profiler 的顯示器名稱變成「Framework 13」→ override 檔**有被讀**；但 `IODisplayEDID`、`DisplayHorizontal/VerticalImageSize`、scale-resolutions **都沒被採用**：CGDisplayScreenSize 仍 796×530 mm、AppleBacklightDisplay 仍 756e6b6e/717、CoreGraphics 只有 1 個模式。override 先保留（無害；還原見 edid-override.sh 註解）。
- **更根本的發現**：這次 WindowServer 向 PhxFB 驗證了一整串 scaled 模式（ioreg `PhxHiDPIRequests`、log `validate:`）：active 2256×1504、scaled 1920×1200 / 1920×1080 / 1680×1050 / 1600×1200 / 1600×1066 / 1440×900 / 1344×896 / 1280×960 / 1280×854 / 2256×1268 / 800×600 / 640×480 …，**只有 scaled 2256×1504 回 ok，其他全部 unsupported**；`PhxHiDPIDetailedCalls` = 5（setDetailedTimings 有被呼叫了）。所有 `sf=0x0`，沒有任何 HiDPI 變體被詢問。
  - 也就是說：macOS 的「縮放解析度」要靠 framebuffer 的**硬體縮放**（IOFBScalerInfo + validateDetailedTiming 接受 scaled 尺寸），PhxFB 不支援縮放，所以除了原生以外全部被拒。就算 EDID/尺寸問題解決，最多只會多一個剛好 2 倍的「看起來像 1128×752」（不需要縮放），1280×853、1504×1003 這種常用的選項仍需要縮放支援。
  - 要真正支援縮放，兩條路：(1) 在 PhxFB 接受 scaled 模式，並在把畫面複製到面板時做縮放（目前是 CPU/SSE 複製，2880×1920→2256×1504 每秒 60 張用 CPU 縮放成本高）；(2) 程式設定 DCN 的 plane scaler（DSCL），讓顯示引擎硬體縮放（nullarc-kext/amd 有 dcn314 的 plan/modeset 標頭可參考，工程大）。
  - EDID 沒被讀的原因也還沒查清楚：需要在 PhxFB 加追蹤（hasDDCConnect / getAttributeForConnection 被問了哪些），看 AppleBacklightDisplay 建立時到底有沒有走 DDC。
- 目前的替代方案仍是：系統設定 → 輔助使用 → 顯示 → 文字大小，或各 App 自己的縮放。

## 風扇噪音（2026-11-21 22:50）
- macOS 讀不到風扇：SMC 的 `FNum = 0`。Framework 的風扇由主機板 EC 依溫度自己控制，macOS 不能看也不能調；只能靠降溫（降功耗）讓它安靜。
- 讀溫度工具：`tools/smcdump.c`（`cc -O2 -framework IOKit -framework CoreFoundation tools/smcdump.c -o /tmp/smcdump`；不帶參數列出所有 T*/F*/P* key，帶參數只讀指定 key，例如 `/tmp/smcdump TC0P`）。VirtualSMC/SMCAMDProcessor 有 TC0P/TC0E/TC0F/TC0T/TC0p（都是同一個 CPU 溫度）。
- 量到的影響：**AMD Power Gadget 開著時封裝約 20.7 W、63°C；關掉後約 11 W、48°C** → 它本身就是最大的熱源（圖表一直重畫）。它每次開機都會自己出現：登入項目清單是空的，loginwindow 的重新開啟清單也找不到，推測是「登入時重新打開視窗」把它帶回來（未確認）。
- 其他降溫方向：剩下跟 CachyOS（5.5 W）的差距主要是 nullarc 接管 GPU 約 4 W（GFXOFF 沒開，有卡住風險）；Claude app 等畫面一直更新的 App 也會讓 WindowServer 和 GPU 忙。
- **使用中（2026-11-21 22:58，Power Gadget 沒開、Claude app 在前景輸出對話）**：封裝 **23.5 W**、C0 14%、TC0P 一路升到 **73°C**；top：WindowServer 24.5%、Claude + 2 個 Helper 約 18%、kernel_task 9.7%。→ 風扇吵主要發生在「畫面一直更新」時：nullarc 的合成路徑（Metal → Vulkan 轉譯）每一幀的 CPU/GPU 成本高。GFXOFF 主要省閒置，對這種情況幫助有限。建議：不用時把 Claude app 這類一直更新畫面的 App 縮到 Dock。

## GFXOFF 實驗（2026-11-21，已執行，**沒有效果**）
- nullarc 的 PhxBringup 和 phxboot 都沒送過 AllowGfxOff(0x19)/DisallowGfxOff(0x1A)，目前是 SMU 預設狀態。nullarc `docs/stage3-acceleration-plan.md` E4b：GFXOFF 允許時 CP_STAT=0x80008000（PFP_BUSY）、CP_STALLED_STAT2=PFP_RCIU_READ_PENDING，0x1A 可解除 stall；後來 E5 查出 PFP 卡住的真正原因是 CP_ME_CNTL 寫錯值。GPU 正常運作後還沒有人測過 GFXOFF。
- 13.0.4 沒有查詢 GFXOFF 狀態的 SMU 訊息；phxctl `smuinfo` 只有 Test/PMFW/DriverIf/EnabledFeatures。也可能 RLC 的 power gating 沒設定，送 0x19 也不會真的關 GFX（未知）。
- 腳本 `gpu/gfxoff-test.sh`（sudo）：基準 60 秒 → 送 0x19 → 90 秒內每 10 秒跑 mtlprobe 確認 GPU 正常並記功耗/溫度/GFXCLK；mtlprobe 失敗或 20 秒沒回應就自動送 0x1A。結果存 `gpu/gfxoff-<時間>.txt`。`--off` 只送 0x1A。狀態不跨重開機。phxctl 路徑是 `/Users/Shared/gpu/phxctl/phxctl`（`/Users/Shared/gpu/phxctl` 是資料夾）。
- **結果（2026-11-21 23:05–23:09，`gpu/gfxoff-1121-230520.txt`、`gpu/gfxoff-1121-230755-noprobe.txt`）**：
  - 0x19 回 OK。90 秒內 mtlprobe 9 次都 4096/4096，WindowServer 正常 → **GFXOFF 允許後 GPU 穩定，沒有卡住**。
  - 功耗**沒有下降**：基準穩定後 10.6–10.8 W；允許後、沒跑 mtlprobe 的取樣 10.7–11.6 W；再補量 60 秒完全不碰 GPU（穩定後）10.5–10.7 W。GetGfxclkFrequency 一直回 800 MHz。
  - 推測（未驗證）：SMU 只是「允許」GFXOFF，GFX 要真的斷電還需要驅動設定 RLC power gating（Linux gfx_v11_0 的 set_powergating_state / RLC PG 設定），nullarc 沒做；或 WindowServer 的合成讓 GFX 一直有工作。要再追就得研究 RLC PG，工程大、風險高。
  - 結論：GFXOFF 沒帶來省電。允許狀態不跨重開機；要手動關掉：`sudo bash gpu/gfxoff-test.sh --off`。

## 睡眠與硬體解碼：可行性評估（2026-11-22）
- **睡眠**：
  - DSDT 第 860–871 行：`_S3` 只在 `CNSB == 0 && DAS3 == 1` 時才定義（BIOS 寫在 NVS 的變數）；`_S4`、`_S5` 無條件存在。Framework 13 AMD 是 Modern Standby（s2idle / S0ix）平台，推測 BIOS 讓 `_S3` 不存在，韌體也沒有 S3 喚醒流程。
  - **已確認（2026-11-22，CachyOS 6.18.55-2-cachyos-lts）**：`/sys/power/mem_sleep` = `[s2idle]`（沒有 `deep`）→ 這台在 Linux 上也沒有 S3，只有 s2idle。`/sys/power/state` = `freeze mem disk`（這裡的 `mem` 對應的就是 s2idle）。
  - macOS 在 x86 上只用 S3 睡眠，不支援 s2idle → 真正的系統睡眠基本上做不到。之前「S3 醒不來」符合這個推論。目前 `pmset` SleepDisabled = 1。
  - 唯一理論上可行的是**休眠（S4，hibernatemode 25：記憶體寫進磁碟後斷電）**：要 OpenCore `Misc → Boot → HibernateMode` + HibernationFixup.kext。難點是 nullarc GPU：喚醒後 GPU 狀態全沒了，phxboot 只在開機時跑，很可能黑屏。nerux-real/nullarc-760M 的 4459c40 有「Register S4 hibernation hooks (PMinit, registerPowerDriver, setPowerState)」，但只是註冊 PM，沒看到恢復 GPU 的完整流程。工程大、風險高。
- **硬體影片解碼**：nullarc README 寫 hardware VCN 4.0.2 video decode「Not yet（WIP）」，BUGS.md B-10 也記錄沒有硬體編解碼。自己做要：PSP 載 VCN 韌體、建 ring、送解碼指令（Linux amdgpu vcn_v4_0 + Mesa radeonsi/radv video 可參考），再接上 VideoToolbox（私有外掛介面，要逆向）。以月計，目前不建議自己做，等 upstream。

## ⚠️ 闔上螢幕／螢幕關閉後畫面不回來（2026-11-22 03:03 發現）
- 測「闔上螢幕用電池」：`tools/lid-battery-log.sh`（每 10 秒記 lid 狀態、電池功率、封裝功耗、C0、溫度）。紀錄（`display/battery-lid-1122.txt`）：開著螢幕、用電池時整機約 4.2 W（InstantAmperage 剛拔電時停在舊值，不可信），封裝 14.5–21 W；03:03:02 闔上後封裝降到約 10.1 W、溫度 55→50°C、電池讀數 19.9 W（也還沒穩定）。03:03:43 之後紀錄中斷。
- **03:03:38 WindowServer 被看門狗結束**（`/Library/Logs/DiagnosticReports/WindowServer-2026-11-22-030338.ips` + `.userspace_watchdog_timeout.spin`）：termination `WATCHDOG`，`is_alive_func returned unhealthy : Display … not ready`。同一刻 kernel log：`IOAccelDisplayPipe::display_change_handler … event = <91>`。之後畫面不回來（phxboot 註解早有記錄：重啟的 WindowServer 在 CoreDisplay 卡住，只能重開機）。
- 使用者重開機時 03:08 出現 watchdog panic（`Kernel-2026-11-22-030811.panic`：no checkins from watchdogd in 188 s, shutdown in progress）。接著 03:08 那次開機 phxboot 跑到 armed 後又被重開 → 03:09:44 判定 previous attempt did not finish → **自動建立 phxboot-off，目前 GPU 接管關閉**。
- **23:19 也一樣**：powerd 23:18:21「Display state: Off」（displaysleep 10 分鐘到期）→ 23:19:01 WindowServer watchdog（40 秒沒 checkin，main thread 無回應）。02:42 也有一次 watchdog panic。
- 兩次都在 22:32 裝了 hidpi2 版 PhxAccel 之後。懷疑（未驗證）：hidpi2 在 connect interrupt 註冊時主動觸發兩次 connect change，螢幕喚醒時 IOFramebuffer 可能重新註冊 → 又觸發 → WindowServer 等不到 display ready。但 log 裡找不到 22:31 之前的「Display state: Off」，無法證明之前螢幕關閉是正常的。
- 下一步：(1) 退回 hidpi1 版 PhxAccel（`sudo bash phxaccel-port/hidpi2-restore.sh`）；(2) `sudo rm /Users/Shared/gpu/phxboot-off` 重開兩次；(3) 用 `pmset displaysleepnow` 測螢幕關閉再按鍵喚醒。成功 → hidpi2 是兇手；失敗 → PhxFB 的顯示電源路徑本身有問題，要修驅動。修好前建議 `sudo pmset -a displaysleep 0`，避免閒置 10 分鐘就把 WindowServer 搞掛。
- **測試結果（2026-11-22 05:03–05:10）**：已退回 hidpi1（sha `3277b0cb`）、移除 phxboot-off、重開兩次（05:05 phxboot armed，WindowServer 用 GPU 合成）。`displaysleep` 已設 0。05:06:36 `pmset displaysleepnow` → **畫面還是沒回來**，05:07:22 WindowServer 被看門狗結束（`WindowServer-2026-11-22-050722.ips` + `.spin`；40 秒沒 checkin，displayState OFF）。沒有 panic，phxboot-off 沒建立。→ **hidpi2 不是兇手**。
  - 主執行緒的 stack（.spin）：CoreDisplay → IOConnectCall → IOGraphicsFamily → **IOAcceleratorFamily2**（經 IOCommandGate）→ 核心等待，狀態 `TH_WAIT|TH_UNINT`，last ran 35.6 s 前 = 螢幕關掉約 10 秒後就卡住（不是喚醒時才卡）。
  - 原因（推測，很有把握）：`phxfb.cpp` 的 `vblFire` 在 `fBlDark`（螢幕關閉）時直接 return、**不再排程**，VBL 從此停掉；IOAccelDisplayPipe 要等下一個 VBL 才能結束待處理的畫面交換（`gPhxVblSeq` 註解也寫「display pipe completes on the next one」），所以永遠等不到。
  - 修正：`vblFire` 只在 `fStopping` 時停，螢幕關閉時照常 tick（只是計時器喚醒，GPU 不做事）。base 用 hidpi1 原始碼（5aac9e8 重新編譯 sha 跟安裝版一樣 `3277b0cb`，可重現），hidpi2 的改動移出（仍在 0aa0046）。新版 sha `8938cdb4…`。安裝：`sudo bash phxaccel-port/vblfix-install.sh`（重開一次）；還原：`sudo bash phxaccel-port/hidpi2-restore.sh`。
- **✅ 修正確認（2026-11-22 05:14 安裝 `8938cdb4`，05:15 開機 phxboot armed）**：05:17:02 powerd「Display state: Off」→ 黑屏 80 秒 → 05:18:22 按 Shift「Display state: On」，**畫面回來**。WindowServer 還是同一個 PID 204（05:15:01 啟動，沒被重啟），DiagnosticReports 沒有新的 watchdog 報告。→ 螢幕關閉問題就是 VBL 停掉造成的，已修好。
  - 目前 `displaysleep 0`（自動關螢幕仍關著）。還沒測：闔上螢幕（clamshell，路徑可能不同）、自動關螢幕（displaysleep 到期）。測過後可以把 displaysleep 改回 10。
- **✅ 闔上螢幕（2026-11-22 05:19:40–05:21:30，約 110 秒，插電中）**：AppleClamshellState Yes→No，WindowServer 一直是 PID 204，VBL 照常（約 60/s），沒有新 watchdog 報告；打開後畫面回來。此次 powerd log 沒記到「Display state: Off」（闔上的路徑跟 displaysleepnow 不同）。

## 闔上螢幕用電池的耗電（2026-11-22 05:22–05:35，VBL 修正版，GPU 接管開著）
- 紀錄 `display/battery-lid-1122b.txt`（`tools/lid-battery-log.sh 780`）。05:22:58 拔電，05:26:35 闔上，05:33:10 打開；畫面回來，WindowServer 一直是 PID 204（**用電池闔上也正常**）。
- 平均（電池讀數約每 60 秒更新一次）：開著 **21.9 W**（封裝 13.0 W）；闔上 **20.8 W**（封裝 15.2 W）；再打開 22.2 W（16.3 W）。電量 100% → 95%（約 12 分鐘）。溫度 60–72°C。
- **闔上只省約 1 W**（大概就是背光）：系統不睡，CPU/GPU 照樣在跑。封裝功耗每約 1–2 分鐘在 10 W ↔ 21 W 之間跳，開著闔上都一樣，可能是開機後才 8 分鐘的背景工作（Spotlight 索引等，未查）。
- 估算：約 21 W ≈ 61 Wh 電池 **2.5–3 小時**（**更正 2026-11-22**：CachyOS sysfs 算出目前滿電約 49 Wh，所以是約 2.3 小時）；闔上放書包 10 分鐘約掉 3–4%，而且機器維持 60–70°C。
- 待查：(1) 封裝 20 W 突波是哪個程序；(2) 螢幕關閉時 WindowServer 會不會因為 VBL 繼續 tick 而照樣合成（比較闔上前後 WindowServer CPU）；(3) 闔上時能否主動降到最低（例如暫停 GPU 合成、降 CPU 上限）。
- **耗電來源（2026-11-22 05:37–05:45，`tools/lid-proc-log.sh`、紀錄 `display/lid-proc-1122.txt`）**：
  - **兇手 1：系統設定 →「顯示器」頁面開著**（HiDPI 實驗時打開，每次開機被「登入時重新打開視窗」帶回來）：`DisplaysExt` 吃 **100% CPU**、連帶一個 `VTDecoderXPCService` 27%。關掉系統設定後封裝從 13–21 W 跳動 → **穩定約 10.8 W**。之前那個「每 1–2 分鐘 10↔21 W 突波」就是它。
  - Claude app 在輸出對話時 WindowServer 合成約 30 幀/秒、封裝 12–13 W；閒置後降到 1 幀/秒。
  - **闔上時 WindowServer 只合成約 1 幀/秒**（跟打開閒置時一樣），VBL 照樣 58–65/s → VBL 修正**沒有**讓它在螢幕關掉時繼續狂畫。
  - 閒置時打開 ≈ 闔上 ≈ **封裝 10.3 W**；CPU 前幾名都很小：kernel_task 約 7%（一直都在，可能是 `-vi2c-force-polling` 觸控板輪詢或其他 kext 計時器，未查）、airportd 約 2%。剩下的 10 W 是目前這套（nullarc GPU 接管 + 沒有深層 C-state）的閒置底線，CachyOS 約 5.5 W。
  - 建議：不要讓系統設定、AMD Power Gadget 開著；關機前把它們關掉，或關掉「登入時重新打開視窗」。

## 壓低閒置底線（2026-11-22，branch `power/idle-floor`）
- 工具 `power/kernel-wakeups.sh`（sudo，只讀：powermetrics interrupts + dtrace kernel_task profile / thread_call / IOTimerEventSource / 中斷來源）。
- 第一次（`wakeups-1122-054832.txt`，剛操作過、Power Gadget 開著）：I2CD 7,741 irq/s（觸控板 2 ms 快速輪詢）。第二次（`wakeups-1122-055053.txt`，先等 45 秒不碰）：**I2CD 561/s**（閒置 50 ms 輪詢，正常）。
- 閒置時：TMR 合計約 2,600/s、IPI 約 3,500/s，集中在偶數 CPU（每個實體核的第一個執行緒）。kernel_task 幾乎全在 idle_thread；有實際工作的只有 `NMXDisplayPipe::performTransaction`（約 1.5% 一顆核，WindowServer 每秒約 30 個 transaction）和 vblFire（排程 119/s：staged 模式每個 VBL 兩次）。→ **沒有哪個 kext 在大量浪費 CPU**。
- 推論：剩下的差距（macOS 約 10 W vs CachyOS 5.5 W）比較可能是**核心只進 C1（macOS 在 AMD 上 MWAIT/HLT）**＋ GPU 接管約 4 W。CachyOS 上 cpu0 閒置大多在 C3。
- 之前「C-state 沒用」的結論（2026-11-21 16:16，C2/C3 都 33 W）是在 SMU 時脈沒限制、封裝被 GFX 2600 MHz / FCLK 1600 MHz 撐在 33 W 時量的，**被蓋過了，要在新基準重測**。目前載入的是監看用的 AMDRyzenCPUPowerManagement [39]＋SMCAMDProcessor [40]，AMDCState [42] 停用（兩者不能同時開）。
- 下一步：`cstate/cstate-on.sh`（[39][40] 停用、[42] 啟用；備份 `config.plist.bak-1122a`；amdcst=3 已在 boot-args），重開後量閒置封裝功耗、C0。代價：AMD Power Gadget 沒資料、SMC 溫度 key 消失（風扇由 EC 控制不受影響）。
- **AMDCState 重測結果（2026-11-22 05:55 開機，05:58:46–06:00:11 閒置取樣，GPU 接管開著，沒有 Power Gadget／系統設定）**：Mode 3、port 0x415，C3 進入約 4,469 次/秒；封裝 **8.4–11.2 W，多數約 10.6 W**——跟 AMDRyzenCPUPowerManagement 時的約 10.3 W **一樣，沒有下降**。C0 反而約 195‰（之前 50–75‰），推測 `inb(0x415)` 沒讓核心真的進 CC6（MPERF 還在數），只是多繞一圈閒置迴圈。
  - **結論（這次是乾淨基準）：核心 C-state 不是瓶頸**。10 W 底線比較可能在 SoC：GPU 接管約 4 W（GPU 關閉時量過 6.8 W）、Data Fabric／記憶體。要再降就是 GPU 電源閘控（RLC PG，見 GFXOFF 段），工程大。
  - 建議還原回監看 kext（溫度、Power Gadget 可用）：`config.plist.bak-1122a`。
  - **已還原（2026-11-22 06:0x）**：config.plist = bak-1122a，[39][40] 啟用、[42] AMDCState 停用（重開後生效）。

## 硬體影片解碼（VCN）階段 0：可行性盤點（2026-11-22，branch `vcn/phase0`）
- upstream：luuumi-dev/nullarc 最新（2026-11-14）都在做 HDMI/DMUB、Metal；nerux-real/nullarc-760M 到 v0.4.0 merge（11-10）。**都還沒碰 VCN**（README「Not yet: hardware VCN 4.0.2 video decode」、BUGS B-10）。
- **使用者空間已經有解碼程式**：系統裡的 RADV（`/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/PhxGPU/nvmtl/libvulkan_radeon.dylib`）含 `radv_video.c`、`VK_KHR_video_queue`、`VK_KHR_video_decode_h264/h265/vp9/av1/queue`、`vcn_unified` 等字串 → Mesa 組 VCN 解碼指令（IB）的部分已經編進去。
  - 卡關點：nullarc 的 winsys 只收 GFX IB（字串 `if (ib._pad || ib.ip_type != AMDGPU_HW_IP_GFX || ib.ip_instance != 0 ...`），VCN IB 會被擋。
- **硬體**：FW13 IP 資訊（`gpu-topology/fw13-ip.txt`，CachyOS AMDGPU_INFO）：HW_IP 6 VCN_DEC v4.0 rings=0、7 VCN_ENC v4.0 rings=1、8 VCN_JPEG v4.0 rings=1 → VCN4 是「unified queue」（解碼也走 enc ring）。IP discovery（Firebat 780M，同 Phoenix）：VCN inst0 v4.0.2，base seg0 0x7800、seg1 0x7e00。
- **PSP 載韌體**：PhxBringup 已有 PSP KM ring + `LOAD_IP_FW`，GFX 韌體就是 `phxctl stage/loadfw <檔> <offset> <size> <fw_type> <tmr offset>` 從使用者空間載的（`/Users/Shared/gpu/bringup5.sh`）。Linux `psp_gfx_if.h`：`GFX_FW_TYPE_VCN = 13`、`GFX_FW_TYPE_VCN0_RAM = 49`。
- **SMU**：`smu_v13_0_4_ppsmc.h`：`PowerUpVcn 0x07`（參數 `inst << 16`，VCN 預設是斷電的）、`PowerDownVcn 0x06`、`PowerUpJpeg 0x22`。PhxBringup 的 `doDbgSmu` 有白名單，**沒有 0x07** → 要改 kext 才能送。
- **Linux 啟動流程（vcn_v4_0.c）**：Phoenix 用 DPG 模式 + `indirect_sram`（PSP 載入時）：把一串暫存器設定寫進 buffer，再請 PSP 用 `VCN0_RAM` 型別套用（`amdgpu_vcn_psp_update_sram`），接著直接寫暫存器設 unified ring（RB base/size/wptr）、fw_shared。`phxctl` 只能讀暫存器（`regs`）→ **階段 1 需要寫 kext 程式**（暫存器寫入、VCN ring、fence）。
- PhxBringup 原始碼注意：`nullarc-kext/` 比 ESP 上的 v0.4.0 release 新（§760M 拓撲段），重編會帶進未驗證的改動；階段 1 可考慮另寫一個獨立的小 kext 透過 PhxBringup 的公開介面做，或用 nullarc-src 對應 v0.4.0 的版本。
- **下一步**：進 CachyOS 跑 `sudo bash ~/fw13-hackintosh/tools/cachyos-vcn-collect.sh`（只讀）：取 `vcn_4_0_2.bin` 和 Linux 的 VCN 韌體版本、dmesg、pm_info、vainfo 到 `/boot/fw13-vcn/`。
- 路線：0 盤點 → 1 kext 啟動 VCN（SMU PowerUpVcn → PSP 載 VCN 韌體 → DPG/SRAM → unified ring → 測 NOP/fence；**高風險**，可能 GPU 卡住/panic，phxboot-off 保護、CachyOS 不受影響）→ 2 winsys 放行 VCN IB 並轉到 VCN ring → 3 mpv/IINA 用 Vulkan 硬解 → 4（非常難）Safari/VideoToolbox。
- **VCN 韌體（2026-11-22 06:25）**：直接從 linux-firmware 下載（gitlab.com/kernel-firmware/linux-firmware main，`amdgpu/vcn_4_0_2.bin`）→ `vcn/fw/vcn_4_0_2.bin`（gitignore，不進 repo），403,856 bytes，sha256 `5633a521…`。common_firmware_header：header v1.0、ip 4.0、ucode_version 0x09118037（解讀：DEC 9、ENC 1.24、VEP 0、rev 55）、ucode_size 0x62890、ucode_array_offset 0x100。→ PSP LOAD_IP_FW 用 offset 256、size 403,600、fw_type 13。Linux 執行時資訊（韌體版本表、dmesg）還沒抓，第 1 階段除錯需要時再跑 `tools/cachyos-vcn-collect.sh`。

## 硬解階段 1：設計與工具（2026-11-22 早上，使用者睡覺時完成，**尚未執行**）
- 設計文件：`vcn/PHASE1.md`。重點：PhxBringup 除錯介面已有任意暫存器讀寫（selector 108）、VRAM 讀寫（102/109）、PSP stage/LOAD_IP_FW（104/105）→ **階段 1 不用寫 kext**，用使用者空間工具。SMU PowerUpVcn(0x07) 不在白名單 → 直接寫 MP1 mailbox 暫存器。
- 工具：`vcn/vcnctl.c`（`clang -O2 -Wall -framework IOKit -framework CoreFoundation vcn/vcnctl.c -o vcn/vcnctl`，binary gitignore）：`check`（只讀：phx-debug、MC base、SMU 查詢、VRAM 0xC000000 起 2 MiB 全 0）、`up [--no-drmkey]`、`regs`、`ringtest`、`down`。
- 測試腳本：`sudo bash vcn/vcn-test.sh [--no-drmkey]`：check → 4 分鐘自動重開 watchdog → up → ringtest → down → 取消 watchdog；紀錄 `vcn/log-<時間>.txt`。要先關 AMD Power Gadget。
- 參考來源：`vcn/ref/`（Linux master 的 vcn_v4_0.c、amdgpu_vcn.[ch]、vcn_4_0_0_offset/sh_mask.h、psp_gfx_if.h、amdgpu_psp.c，gitignore）。raw.githubusercontent 會 429，改用 git.kernel.org/…/plain/。
- 已驗算（主機端）：fw_shared 結構 148 bytes（sq@16、smu@120、drm@124）、DPG 內部位址 VCPU_CNTL→0xd6、GFX10_ADDR_CONFIG→0xc042、LMI_CTRL→0x1f0。
- 主要風險：4.0.2 的 DRM key/ASD handshaking（nullarc 沒載 ASD）、沒設 doorbell、SMU mailbox 沒鎖。見 PHASE1.md。

### 硬解階段 1 結果（2026-11-22 12:56）✅ VCN 活了
- `vcn/vcn-test.sh` 第一次跑：check 停在「VRAM 0xC000000 起全非 0」——carve-out 開機不清 0、熱重開後 CachyOS 殘留。改成「3 秒內沒變」判定 + up 先清 0（034d198）。
- 第二次（log `vcn/log-1122-125650.txt`）：PSP 載 VCN 韌體 status 0（fw_addr 0x8008a10000）→ SMU PowerUpVcn OK → DPG SRAM 經 PSP VCN0_RAM 套用（`UVD_GFX10_ADDR_CONFIG` 從 0x4345 變 0x242，證明 SRAM 有生效）→ unified ring → **ringtest：RPTR 0 → 0x40，2 ms**。down 正常、PowerDownVcn OK、系統沒事。
- 預設參數（含 DRM key inject / ASD handshaking）就過了，不需要 `--no-drmkey`、不需要 doorbell（直接寫 WPTR）。
- DPG 模式下 VCPU 區的暫存器（UVD_STATUS、MASTINT_EN、LMI_CTRL）直接讀回 0xdeadbeef、VCPU_CNTL 0xffffffff，是正常的（要經 DPG 間接讀）。
- 腳本最後一行 `$RT（` 被 bash 當成變數名的一部分 → 改成 `${RT}`。
- 下一步（階段 2）：在 ring 上送一個真的 IB（先試 VCN_ENC_CMD_IB + fence 寫回 VRAM），再讓 nullarc winsys 放行 VCN IB。

### 硬解階段 2 設計（2026-11-22）
- `vcn/PHASE2.md`：2a 從使用者空間送 decode IB + fence（`vcnctl ibtest`，vmid 0、全在 VRAM、寫 HDP flush）；2b kext `vmBind` 把同一份 page table 也掛到 MMHUB（VCN 走 MMHUB，kext 現在只設 GC）；2c kext/winsys 放行 `AMDGPU_HW_IP_VCN_ENC`（nullarc 的 Mesa 原始碼不在 repo）。
- Safari 等走 VideoToolbox，2c 之後受益的是 Vulkan 解碼（mpv/ffmpeg）；VideoToolbox 外掛是階段 3。
- `vcn-test.sh` 現在 ringtest 過了會接著跑 ibtest；`vcnctl mmhub` 只讀 MMHUB 狀態。都還沒在硬體上跑。

### 硬解階段 2a 結果（2026-11-22 13:02）✅ VCN 執行了 decode IB
- log `vcn/log-1122-130235.txt`：create msg job → fence 1（1 ms，RPTR 0x40→0x80）；destroy msg job → fence 2（1 ms，0x80→0xc0）。up=0 ringtest=0 ibtest=0，down 正常，WindowServer 沒事。
- 證明：韌體看得懂 unified queue 的 checksum/engine-info 標頭、能從 VRAM 讀 IB 和 msg、能寫 fence（vmid 0、MC 位址、HDP flush 有效）。跟 Linux 的 IB test 判定標準一樣（只看 fence，不驗 msg 內容）。
- 小觀察：上次 down 後再跑，開電前 RPTR/WPTR 還是 0x40、POWER_STATUS 0x101 → PowerDownVcn 不會清暫存器，up 會重設，沒影響。
- 下一步 2b：先跑只讀的 `vcnctl mmhub` 看 MMHUB 的 VM context 現況。

### 硬解階段 2b：MMHUB 現況（2026-11-22，`vcnctl mmhub` 第一次）
- FB_LOCATION 0x8000–0x80ff（MC 0x80_0000_0000 起 4 GiB）、FB_OFFSET 0x7a0（carve-out 實體位址 0x7_A000_0000）、AGP 關、SYSTEM_APERTURE LOW 0x200000（=MC 0x80_0000_0000>>18）。
- MMVM_CONTEXT0..15 CNTL 全是 0x01fffe00（**沒啟用**）、PT_BASE 0 → VCN 目前只能用 vmid 0（MC 位址）。CNTL 預設位元跟 GC VMID8 的 0x01fffe07 一致 → 欄位格式相同，啟用時寫 0x01fffe07（depth 3）或 0x01fffe01（depth 0 平面表）。
- 已擴充 `mmhub` 加印 L1 TLB / L2 CNTL / protection fault / invalidate eng17，判斷 MMHUB 全域 VM 是否已由開機韌體打開（決定 2b 測試要不要碰全域暫存器——碰了可能影響顯示）。
- MMHUB 全域第二次讀（擴充版）：L1_TLB 0x501、L2_CNTL 0x80602（L2 關）、CNTL4 0xc1、invalidate range 0、預設頁 0 → 開機韌體只開了實體模式。2b 要照 Linux 改全域（值跟 GC 現值相同）。`vcnctl vmtest` 寫好（備份→設定→vmid 1 送 job，fence 寫 VRAM 和系統記憶體→還原），`vcn-test.sh --vm` 會跑；未在硬體上跑。細節在 `vcn/PHASE2.md`。

### 硬解階段 2b 第一次（2026-11-22 13:08，log `vcn/log-1122-130800.txt`）✗ 但有線索
- MMHUB 全域設定、context 1、eng17 invalidate（ACK 0x2）都寫進去了，畫面沒事，結束後 19 個暫存器全部還原成功。
- job 1（vmid 1、fence 用 VA）：RPTR 0xc0→0x100 有動，但 fence 沒寫、PROT_FAULT_STATUS 0。
- 判斷：FENCE 是 ring 層的命令，位址照 ring 的 vmid 0 解讀（Linux 的 fence 也是核心位址），只有 IB 內容用 vmid 1。→ 改 vmtest：fence 一律 MC；job 1 IB 在 VRAM（經 VA）、job 2 IB 在系統記憶體（經 VA）、job 3 對照組（範圍外 VA，看有沒有 fault 記錄）；開頭先印上次的 scratch 頁，看 fence 是否被導到那裡。

### 硬解階段 2b 結果（2026-11-22 13:09，log `vcn/log-1122-130919.txt`）✅ VCN 經 MMHUB page table 讀 IB
- 上次的 scratch 頁是空的 → VA 當 fence 時沒被導到預設頁（寫去哪不重要：fence 一律 MC 位址）。
- job 1：vmid 1，IB 在 VRAM（經 VA）→ fence 0x11 ✅。job 2：vmid 1，**IB 在系統記憶體**（經 VA，PTE SYSTEM|SNOOPED|MTYPE4）→ fence 0x22 ✅。兩次都沒有 fault。
- job 3 對照組（範圍外 VA 0x40_1000_0000）：PROT_FAULT_STATUS 0x103933、ADDR 0x4010000（= VA>>12）→ 轉換路徑確實在作用。**但 VCN 卡住**（RPTR 停在 0x140、down 時 POWER_STATUS 等不到 1）；PowerDownVcn 照樣 OK，畫面沒事。→ kext 版要有「VCN 卡住 → SMU 斷電再重新 up」的恢復流程。
- MMHUB 19 個暫存器全部還原。結論：kext 只要在 `vmBind` 時把同一份 4 級 page table 也掛到 MMHUB 同一個 VMID（加上一次性的 MMHUB 全域設定 L1 0x1859 / L2 0x80e01 / CNTL3 0x80130009 / CNTL4 0x1 / eng17 range），VCN 就能直接吃 RADV 的 GPU VA。fence 用 VRAM MC 位址。
- 2c 前置調查：nullarc 原始碼在 `nullarc-src/x/nullarc-main`（gitignored）。RADV 的 Darwin winsys 不在裡面，是「Mesa f5cb8ee0 + Cobalt64 的 darwin patches 0001–0009 + `mesa-patches-phoenix/0001–0007`」，GFX-only 檢查在 `src/amd/common/darwin/ac_darwin_drm.c` 一帶。Cobalt64 patches 本機沒有，要另外抓；重編 Mesa 要 meson/ninja/mako/glslang（README 有指令）。

### 硬解階段 3 可行性研究（2026-11-22）✗ 不建議做
- 詳細在 `vcn/PHASE3.md`。實測（`vcn/phase3/vtprobe.m`）：VideoToolbox 對所有 codec 都沒有硬解，H.264/HEVC 全是 CPU 軟解（VCP 軟體解碼器），要求硬體會回 -12906。
- AppleGVA 靠加速器節點的 `IOVARendererID` 選 AMD VA 驅動；這台沒有。AMDRadeonVADriver2 走 IOAccelerator 私有介面（`IOAccelVideoContext*`），而且產生的是 VCN2/3 命令；要用它就得在 kext 重做 IOAcceleratorFamily2 的 video context 並翻譯成 VCN4 unified queue——規模遠超階段 1–2，全靠逆向。MediaExtension / 第三方外掛蓋不掉內建 codec、Safari/桌布不會載；注入要關 SIP。
- 另外發現 nullarc 的 Metal = `PhxGPU/NVMTLDriver.bundle` → RADV → kext 私有 ABI（不是 IOAccelerator family）。
- 決定：硬解停在階段 2（2c 只對 mpv/ffmpeg 有用，暫緩）。動態桌布改從耗電面處理：量 Aerial vs 靜態，必要時改 HEIC 時間動態桌布。
