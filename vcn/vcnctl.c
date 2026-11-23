/*
 * vcnctl — 硬解階段 1：在 macOS 上啟動 Phoenix 的 VCN 4.0.2（影片解碼器）並做 ring test。
 *
 * 全部透過 PhxBringup 既有的除錯介面（phxdebug=1、root，user client 'N48N'，跟 phxctl 同一套 selector）：
 *   SEL_READREGS(2) 讀暫存器、SEL_DBG_WRITE_REG(108) 寫暫存器、SEL_DBG_VRAM_READ/WRITE(102/109) 讀寫 BAR0 VRAM、
 *   SEL_DBG_FW_STAGE(104) + SEL_DBG_PSP_LOADIPFW(105) 透過 PSP 載韌體、SEL_DBG_SMU(100) 查 SMU（白名單）。
 * SMU 的 PowerUpVcn(0x07)/PowerDownVcn(0x06) 不在 kext 白名單，改成直接寫 MP1 mailbox 暫存器（同 kext 的
 * smuMessage：MSG 0x16282、ARG 0x16292、RESP 0x1629A）。
 *
 * 流程照 Linux drivers/gpu/drm/amd/amdgpu/vcn_v4_0.c（PSP 載入 + DPG + indirect SRAM，Phoenix 的路徑）：
 *   1. PSP LOAD_IP_FW：vcn_4_0_2.bin[0x100:+ucode_size]，fw_type 13（GFX_FW_TYPE_VCN）
 *   2. SMU PowerUpVcn(inst<<16)
 *   3. fw_shared（unified queue、SMU DPM APU、4.0.2 的 DRM key workaround）寫進 VRAM
 *   4. UVD_POWER_STATUS：anti-hang、PG_MODE|PG_EN（直接寫）
 *   5. 把 vcn_v4_0_start_dpg_mode 的 DPG 暫存器設定組成 (offset, value) 清單，PSP LOAD_IP_FW fw_type 49（VCN0_RAM）
 *   6. unified ring：RB_BASE/SIZE、RB_ENABLE、RPTR/WPTR（直接寫，不用 doorbell）
 *   ringtest：寫 VCN_ENC_CMD_END + 63 個 NOP，WPTR += 64，看 RPTR 有沒有跟上（amdgpu_vcn_enc_ring_test_ring）
 *
 * 記憶體：VRAM（UMA carve-out）BAR0 窗口 0xC000000 起（TMR 0x8000000+64MiB 之後，256MiB 窗口內，nullarc 沒用到；
 * `check` 會先確認整段是 0）。VCN 用 MC 位址 = phx-fb-mc-base + offset。
 *
 * 編譯：clang -O2 -Wall -framework IOKit -framework CoreFoundation vcn/vcnctl.c -o vcn/vcnctl
 * 用法（root）：vcnctl check | up [--no-drmkey] | regs | ringtest | down
 */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#define UC_TYPE 0x4E34384Eu
#define SEL_HELLO 0
#define SEL_READREGS 2
#define SEL_DBG_SMU 100
#define SEL_DBG_VRAM_READ 102
#define SEL_DBG_FW_STAGE 104
#define SEL_DBG_PSP_LOADIPFW 105
#define SEL_DBG_WRITE_REG 108
#define SEL_DBG_VRAM_WRITE 109
#define SEL_DBG_SYSMEM 111

/* ---- 位址 ---- */
#define VCN_BASE0 0x7800u /* IP discovery VCN inst0 segment 0（Phoenix，0x15bf；nullarc 的 GC/MP 位址也是這份） */
#define VCN_BASE1 0x7e00u /* segment 1：這裡用到的暫存器 BASE_IDX 都是 1 */
#define R(reg) (VCN_BASE1 + (reg))

/* vcn_4_0_0_offset.h（全部 BASE_IDX 1） */
#define regUVD_POWER_STATUS 0x0002
#define regUVD_DPG_PAUSE 0x0014
#define regUVD_GFX10_ADDR_CONFIG 0x0042
#define regVCN_RB1_DB_CTRL 0x0072
#define regVCN_RB_ENABLE 0x0085
#define regUVD_RB_RPTR 0x00ac
#define regUVD_RB_WPTR 0x00ad
#define regUVD_CGC_GATE 0x00c1
#define regUVD_CGC_CTRL 0x00c2
#define regUVD_MASTINT_EN 0x00e1
#define regUVD_RB_BASE_LO 0x00ea
#define regUVD_RB_BASE_HI 0x00eb
#define regUVD_RB_SIZE 0x00ec
#define regUVD_STATUS 0x0143
#define regUVD_VCPU_CACHE_OFFSET0 0x0180
#define regUVD_VCPU_CACHE_SIZE0 0x0181
#define regUVD_VCPU_CACHE_OFFSET1 0x0182
#define regUVD_VCPU_CACHE_SIZE1 0x0183
#define regUVD_VCPU_CACHE_OFFSET2 0x0184
#define regUVD_VCPU_CACHE_SIZE2 0x0185
#define regUVD_VCPU_NONCACHE_OFFSET0 0x0192
#define regUVD_VCPU_NONCACHE_SIZE0 0x0193
#define regUVD_VCPU_CNTL 0x0196
#define regUVD_MPC_CNTL 0x01d4
#define regUVD_MPC_SET_MUXA0 0x01d6
#define regUVD_MPC_SET_MUXB0 0x01d8
#define regUVD_MPC_SET_MUX 0x01da
#define regUVD_LMI_VCPU_NC0_64BIT_BAR_LOW 0x0240
#define regUVD_LMI_VCPU_NC0_64BIT_BAR_HIGH 0x0241
#define regUVD_LMI_VCPU_CACHE_64BIT_BAR_LOW 0x0244
#define regUVD_LMI_VCPU_CACHE_64BIT_BAR_HIGH 0x0245
#define regUVD_LMI_VCPU_CACHE1_64BIT_BAR_LOW 0x0270
#define regUVD_LMI_VCPU_CACHE1_64BIT_BAR_HIGH 0x0271
#define regUVD_LMI_VCPU_CACHE2_64BIT_BAR_LOW 0x0274
#define regUVD_LMI_VCPU_CACHE2_64BIT_BAR_HIGH 0x0275
#define regUVD_LMI_CTRL2 0x02ae
#define regUVD_LMI_CTRL 0x02b0

/* vcn_4_0_0_sh_mask.h */
#define UVD_POWER_STATUS__UVD_POWER_STATUS_MASK 0x00000003u
#define UVD_POWER_STATUS__UVD_PG_MODE_MASK 0x00000004u
#define UVD_POWER_STATUS__UVD_PG_EN_MASK 0x00000100u
#define UVD_VCPU_CNTL__PRB_TIMEOUT_VAL__SHIFT 0x14
#define UVD_VCPU_CNTL__CLK_EN_MASK 0x00000200u
#define UVD_VCPU_CNTL__BLK_RST_MASK 0x10000000u
#define UVD_LMI_CTRL__WRITE_CLEAN_TIMER__SHIFT 0x0
#define UVD_LMI_CTRL__WRITE_CLEAN_TIMER_EN_MASK 0x00000100u
#define UVD_LMI_CTRL__REQ_MODE_MASK 0x00000200u
#define UVD_LMI_CTRL__MASK_MC_URGENT_MASK 0x00001000u
#define UVD_LMI_CTRL__DATA_COHERENCY_EN_MASK 0x00002000u
#define UVD_LMI_CTRL__CRC_RESET_MASK 0x00004000u
#define UVD_LMI_CTRL__VCPU_DATA_COHERENCY_EN_MASK 0x00200000u
#define UVD_MPC_CNTL__REPLACEMENT_MODE__SHIFT 0x3
#define UVD_LMI_CTRL2__RE_OFLD_MIF_WR_REQ_NUM__SHIFT 0x11
#define UVD_MASTINT_EN__VCPU_EN_MASK 0x00000002u
#define VCN_RB_ENABLE__RB1_EN_MASK 0x00000004u

/* amdgpu_vcn.h / vcn_v4_0.c */
#define VCN_VID_SOC_ADDRESS_2_0 0x1fb00u
#define VCN_AON_SOC_ADDRESS_2_0 0x1f800u
#define VCN_VID_IP_ADDRESS_2_0 0x0u
#define VCN_AON_IP_ADDRESS_2_0 0x30000u
#define AMDGPU_VCN_STACK_SIZE (128u * 1024u)
#define AMDGPU_VCN_CONTEXT_SIZE (512u * 1024u)
#define VCN_ENC_CMD_NO_OP 0x00000000u
#define VCN_ENC_CMD_END 0x00000001u
#define AMDGPU_FW_SHARED_FLAG_0_UNIFIED_QUEUE (1u << 2)
#define AMDGPU_FW_SHARED_FLAG_0_DRM_KEY_INJECT (1u << 4)
#define AMDGPU_VCN_SMU_DPM_INTERFACE_FLAG (1u << 11)
#define AMDGPU_VCN_SMU_DPM_INTERFACE_APU 1
#define AMDGPU_DRM_KEY_INJECT_WORKAROUND_VCNFW_ASD_HANDSHAKING 2
#define FW_QUEUE_RING_RESET 1
#define FW_QUEUE_DPG_HOLD_OFF 2
#define GB_ADDR_CONFIG 0x00000242u /* PhxBringup kGbAddrConfig（760M/780M） */

/* psp_gfx_if.h */
#define GFX_FW_TYPE_VCN 13
#define GFX_FW_TYPE_VCN0_RAM 49

/* SMU 13.0.4（smu_v13_0_4_ppsmc.h；mailbox = PhxNativeABI.h PHX_SMU_*_REG） */
#define SMU_MSG_REG 0x16282u
#define SMU_ARG_REG 0x16292u
#define SMU_RESP_REG 0x1629Au
#define PPSMC_MSG_PowerDownVcn 0x06
#define PPSMC_MSG_PowerUpVcn 0x07
#define PPSMC_MSG_GetEnabledSmuFeatures 0x12

/* ---- VRAM 配置（BAR0 byte offset） ---- */
#define WIN_OFF 0x0C000000u
#define WIN_CHECK 0x00200000u /* check 會確認前 2 MiB 3 秒內沒被改 */
#define VCPU_OFF (WIN_OFF + 0x0)                                               /* stack + context */
#define FWSHARED_OFF (VCPU_OFF + AMDGPU_VCN_STACK_SIZE + AMDGPU_VCN_CONTEXT_SIZE) /* 0xC0A0000，接在 VCPU BO 後 */
#define RING_OFF (WIN_OFF + 0x00100000u)
#define RING_BYTES 0x4000u /* 16 KiB = 4096 dwords */
#define FWBUF_VCN 0x000000u   /* fw_buf 內暫存韌體的位置 */
#define FWBUF_SRAM 0x100000u  /* fw_buf 內暫存 DPG SRAM 清單的位置 */

/* amdgpu_vcn4_fw_shared（amdgpu_vcn.h，沒有 packed，自然對齊） */
struct fw_shared_unified_queue { uint8_t is_enabled, queue_mode, queue_status, padding[5]; };
struct fw_shared_fw_logging { uint8_t is_enabled; uint32_t addr_lo, addr_hi, size; };
struct fw_shared_rb_setup { uint32_t is_rb_enabled_flags; uint32_t u[12]; };
struct fw_shared_smu_interface_info { uint8_t smu_interface_type, padding[3]; };
struct fw_shared_drm_key_wa { uint8_t method, reserved[3]; };
struct fw_shared_queue_decouple { uint8_t is_enabled, reserved[7]; };
struct vcn4_fw_shared {
   uint32_t present_flag_0;
   uint8_t pad[12];
   struct fw_shared_unified_queue sq;
   uint8_t pad1[8];
   struct fw_shared_fw_logging fw_log;
   uint8_t pad2[20];
   struct fw_shared_rb_setup rb_setup;
   struct fw_shared_smu_interface_info smu_dpm_interface;
   struct fw_shared_drm_key_wa drm_key_wa;
   uint8_t pad3[9];
   struct fw_shared_queue_decouple decouple;
};

static io_connect_t conn;
static uint64_t fb_mc_base;
static uint32_t hdp_flush_dword; /* phx-hdp-flush-dword：寫 0 讓 BAR0 寫入落到 DRAM（kext hdpFlush） */
static int failed;

static double now_ms(void)
{
   struct timespec ts;
   clock_gettime(CLOCK_MONOTONIC, &ts);
   return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

static int open_kext(void)
{
   io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("PhxBringup"));
   if (!svc) {
      fprintf(stderr, "找不到 PhxBringup service\n");
      return -1;
   }
   CFTypeRef hp = IORegistryEntryCreateCFProperty(svc, CFSTR("phx-hdp-flush-dword"), kCFAllocatorDefault, 0);
   if (hp && CFGetTypeID(hp) == CFNumberGetTypeID())
      CFNumberGetValue((CFNumberRef)hp, kCFNumberSInt32Type, &hdp_flush_dword);
   if (hp)
      CFRelease(hp);
   CFTypeRef p = IORegistryEntryCreateCFProperty(svc, CFSTR("phx-fb-mc-base"), kCFAllocatorDefault, 0);
   if (p && CFGetTypeID(p) == CFNumberGetTypeID())
      CFNumberGetValue((CFNumberRef)p, kCFNumberSInt64Type, &fb_mc_base);
   if (p)
      CFRelease(p);
   CFTypeRef d = IORegistryEntryCreateCFProperty(svc, CFSTR("phx-debug"), kCFAllocatorDefault, 0);
   int dbg = d && d == kCFBooleanTrue;
   if (d)
      CFRelease(d);
   kern_return_t kr = IOServiceOpen(svc, mach_task_self(), UC_TYPE, &conn);
   IOObjectRelease(svc);
   if (kr) {
      fprintf(stderr, "IOServiceOpen: 0x%08x\n", kr);
      return -1;
   }
   uint64_t in[2] = {1, 0}, out[4];
   uint32_t n = 4;
   kr = IOConnectCallScalarMethod(conn, SEL_HELLO, in, 2, out, &n);
   if (kr) {
      fprintf(stderr, "Hello: 0x%08x\n", kr);
      return -1;
   }
   if (!dbg) {
      fprintf(stderr, "PhxBringup 的 phx-debug 不是 Yes（boot-args 要有 phxdebug=1）\n");
      return -1;
   }
   if (fb_mc_base != 0x8000000000ull) {
      fprintf(stderr, "phx-fb-mc-base = 0x%llx，不是預期的 0x8000000000，停止\n", (unsigned long long)fb_mc_base);
      return -1;
   }
   return 0;
}

static uint32_t rreg(uint32_t reg)
{
   uint64_t in[3] = {reg, 1, 0xFFFFFFFFull};
   uint32_t v = 0xDEADDEAD;
   size_t sz = 4;
   kern_return_t kr = IOConnectCallMethod(conn, SEL_READREGS, in, 3, NULL, 0, NULL, NULL, &v, &sz);
   if (kr) {
      printf("  !! rreg 0x%x err 0x%08x\n", reg, kr);
      failed = 1;
   }
   return v;
}

static uint32_t wreg(uint32_t reg, uint32_t val)
{
   uint64_t in[2] = {reg, val}, out[1] = {0};
   uint32_t n = 1;
   kern_return_t kr = IOConnectCallScalarMethod(conn, SEL_DBG_WRITE_REG, in, 2, out, &n);
   if (kr) {
      printf("  !! wreg 0x%x = 0x%08x err 0x%08x\n", reg, val, kr);
      failed = 1;
   }
   return (uint32_t)out[0];
}

static void wreg_log(const char *name, uint32_t reg, uint32_t val)
{
   uint32_t rb = wreg(reg, val);
   printf("  wreg %-26s [0x%05x] = 0x%08x  readback 0x%08x\n", name, reg, val, rb);
}

static int vram_read(uint32_t off, uint32_t *buf, uint32_t count)
{
   uint64_t in[2] = {off, count};
   size_t sz = count * 4;
   kern_return_t kr = IOConnectCallMethod(conn, SEL_DBG_VRAM_READ, in, 2, NULL, 0, NULL, NULL, buf, &sz);
   return kr ? (int)kr : 0;
}

static int vram_write(uint32_t off, uint32_t v)
{
   uint64_t in[2] = {off, v};
   kern_return_t kr = IOConnectCallScalarMethod(conn, SEL_DBG_VRAM_WRITE, in, 2, NULL, NULL);
   if (kr) {
      printf("  !! vramw +0x%x err 0x%08x\n", off, kr);
      failed = 1;
   }
   return kr ? (int)kr : 0;
}

static int vram_write_block(uint32_t off, const void *src, uint32_t bytes)
{
   const uint32_t *w = (const uint32_t *)src;
   for (uint32_t i = 0; i < bytes / 4; i++)
      if (vram_write(off + i * 4, w[i]))
         return -1;
   return 0;
}

static int vram_zero(uint32_t off, uint32_t bytes)
{
   for (uint32_t i = 0; i < bytes; i += 4)
      if (vram_write(off + i, 0))
         return -1;
   return 0;
}

/* 跟 kext smuMessage 一樣的 mailbox 流程：等上一個回應、清 RESP、寫 ARG、寫 MSG、等 RESP */
static int smu_raw(uint32_t msg, uint32_t arg, const char *what)
{
   double t0 = now_ms();
   uint32_t r;
   while ((r = rreg(SMU_RESP_REG)) == 0 && now_ms() - t0 < 1000)
      usleep(1000);
   if (r == 0) {
      printf("  !! SMU mailbox 忙（RESP 一直是 0），不送 %s\n", what);
      return -1;
   }
   wreg(SMU_RESP_REG, 0);
   wreg(SMU_ARG_REG, arg);
   wreg(SMU_MSG_REG, msg);
   t0 = now_ms();
   while ((r = rreg(SMU_RESP_REG)) == 0 && now_ms() - t0 < 2000)
      usleep(1000);
   uint32_t out = rreg(SMU_ARG_REG);
   printf("  smu %-14s msg 0x%02x arg 0x%08x -> resp 0x%02x%s  out 0x%08x  %.0f ms\n", what, msg, arg, r,
          r == 1 ? " (OK)" : r == 0 ? " (沒有回應)" : r == 0xFE ? " (UnknownCmd)" : r == 0xFD ? " (CmdRejectedPrereq)" :
          r == 0xFF ? " (Failed)" : "", out, now_ms() - t0);
   return r == 1 ? 0 : -1;
}

/* SOC15_DPG_MODE_OFFSET：把 SOC15 暫存器換成 DPG SRAM 的內部位址（video range 先判斷，同 Linux 巨集） */
static uint32_t dpg_offset(uint32_t reg)
{
   uint32_t addr = ((VCN_BASE1 + reg) << 2) & 0xFFFFF, internal;
   if (addr >= VCN_VID_SOC_ADDRESS_2_0 && addr < VCN_VID_SOC_ADDRESS_2_0 + 0x2600)
      internal = addr - VCN_VID_SOC_ADDRESS_2_0 + VCN_VID_IP_ADDRESS_2_0;
   else if (addr >= VCN_AON_SOC_ADDRESS_2_0 && addr < VCN_AON_SOC_ADDRESS_2_0 + 0x600)
      internal = addr - VCN_AON_SOC_ADDRESS_2_0 + VCN_AON_IP_ADDRESS_2_0;
   else
      internal = addr;
   return internal >> 2;
}

static uint32_t sram[512];
static uint32_t nsram;
static void dpg(const char *name, uint32_t reg, uint32_t val)
{
   sram[nsram++] = dpg_offset(reg);
   sram[nsram++] = val;
   printf("  sram %-34s off 0x%05x = 0x%08x\n", name, dpg_offset(reg), val);
}

/* fw_buf 暫存 + PSP LOAD_IP_FW（跟 phxctl loadfw 一樣） */
static int psp_load(const void *data, uint32_t size, uint32_t fwtype, uint32_t bufoff, const char *what)
{
   const uint8_t *p = (const uint8_t *)data;
   for (uint32_t done = 0; done < size;) {
      uint32_t chunk = size - done > 4096 ? 4096 : size - done;
      uint64_t in[1] = {bufoff + done};
      kern_return_t kr = IOConnectCallMethod(conn, SEL_DBG_FW_STAGE, in, 1, p + done, chunk, NULL, NULL, NULL, NULL);
      if (kr) {
         printf("  !! stage %s @fwbuf+0x%x err 0x%08x\n", what, bufoff + done, kr);
         return -1;
      }
      done += chunk;
   }
   uint64_t lin[3] = {fwtype, bufoff, size}, out[4] = {0, 0, 0, 0};
   uint32_t n = 4;
   kern_return_t kr = IOConnectCallScalarMethod(conn, SEL_DBG_PSP_LOADIPFW, lin, 3, out, &n);
   printf("  psp LOAD_IP_FW %-10s type %u size %u @fwbuf+0x%x -> kr 0x%08x status 0x%08x %llu us fw_addr 0x%08x%08x\n",
          what, fwtype, size, bufoff, kr, (uint32_t)out[0], (unsigned long long)out[1], (uint32_t)out[3],
          (uint32_t)out[2]);
   return (kr || out[0]) ? -1 : 0;
}

static void dump_regs(void)
{
   static const struct { const char *n; uint32_t r; } regs[] = {
      {"UVD_POWER_STATUS", regUVD_POWER_STATUS}, {"UVD_STATUS", regUVD_STATUS},
      {"UVD_DPG_PAUSE", regUVD_DPG_PAUSE},       {"VCN_RB_ENABLE", regVCN_RB_ENABLE},
      {"UVD_RB_BASE_LO", regUVD_RB_BASE_LO},     {"UVD_RB_BASE_HI", regUVD_RB_BASE_HI},
      {"UVD_RB_SIZE", regUVD_RB_SIZE},           {"UVD_RB_RPTR", regUVD_RB_RPTR},
      {"UVD_RB_WPTR", regUVD_RB_WPTR},           {"VCN_RB1_DB_CTRL", regVCN_RB1_DB_CTRL},
      {"UVD_VCPU_CNTL", regUVD_VCPU_CNTL},       {"UVD_MASTINT_EN", regUVD_MASTINT_EN},
      {"UVD_LMI_CTRL", regUVD_LMI_CTRL},         {"UVD_GFX10_ADDR_CONFIG", regUVD_GFX10_ADDR_CONFIG},
   };
   for (size_t i = 0; i < sizeof regs / sizeof regs[0]; i++)
      printf("  %-24s [0x%05x] = 0x%08x\n", regs[i].n, R(regs[i].r), rreg(R(regs[i].r)));
}

static uint8_t *read_file(const char *path, size_t *len)
{
   FILE *f = fopen(path, "rb");
   if (!f)
      return NULL;
   fseek(f, 0, SEEK_END);
   long n = ftell(f);
   fseek(f, 0, SEEK_SET);
   uint8_t *b = malloc((size_t)n);
   if (b && fread(b, 1, (size_t)n, f) != (size_t)n) {
      free(b);
      b = NULL;
   }
   fclose(f);
   *len = (size_t)n;
   return b;
}

static int cmd_check(void)
{
   printf("== check（只讀）\n");
   printf("  phx-fb-mc-base 0x%llx  phx-debug Yes\n", (unsigned long long)fb_mc_base);
   uint64_t in[2] = {PPSMC_MSG_GetEnabledSmuFeatures, 0}, out[2] = {0, 0};
   uint32_t n = 2;
   kern_return_t kr = IOConnectCallScalarMethod(conn, SEL_DBG_SMU, in, 2, out, &n);
   printf("  SMU GetEnabledSmuFeatures(lo) -> kr 0x%08x resp 0x%02llx out 0x%08llx\n", kr, (unsigned long long)out[0],
          (unsigned long long)out[1]);
   printf("  fw_shared 大小 %zu bytes（sq @%zu, smu_dpm @%zu, drm_key @%zu）\n", sizeof(struct vcn4_fw_shared),
          offsetof(struct vcn4_fw_shared, sq), offsetof(struct vcn4_fw_shared, smu_dpm_interface),
          offsetof(struct vcn4_fw_shared, drm_key_wa));
   printf("  配置：VCPU BO +0x%x（MC 0x%llx）fw_shared +0x%x  ring +0x%x（%u bytes）\n", VCPU_OFF,
          (unsigned long long)(fb_mc_base + VCPU_OFF), FWSHARED_OFF, RING_OFF, RING_BYTES);
   /* 這段 VRAM 是系統記憶體切出來的 carve-out，開機不會清 0（熱重開後 Linux 的殘留還在）。
      所以不要求全 0，而是：讀兩次、隔 3 秒，內容完全沒變 = 沒人在用（up 會先清 0 再用）；有變 = 有人在寫，停止。 */
   static uint32_t snap[WIN_CHECK / 4];
   uint32_t buf[256], nz = 0, ff = 0, diff = 0, firstdiff = 0;
   for (int pass = 0; pass < 2; pass++) {
      if (pass)
         sleep(3);
      for (uint32_t off = WIN_OFF; off < WIN_OFF + WIN_CHECK; off += sizeof buf) {
         if (vram_read(off, buf, 256)) {
            printf("  !! vram read +0x%x 失敗\n", off);
            return 1;
         }
         uint32_t *s0 = &snap[(off - WIN_OFF) / 4];
         for (int i = 0; i < 256; i++) {
            if (!pass) {
               s0[i] = buf[i];
               nz += buf[i] != 0;
               ff += buf[i] == 0xFFFFFFFFu;
            } else if (s0[i] != buf[i]) {
               if (!diff)
                  firstdiff = off + i * 4;
               diff++;
            }
         }
      }
   }
   printf("  VRAM +0x%x..+0x%x：非 0 %u、0xFFFFFFFF %u（共 %u dword）；前 8 個：", WIN_OFF, WIN_OFF + WIN_CHECK, nz, ff,
          WIN_CHECK / 4);
   for (int i = 0; i < 8; i++)
      printf(" %08x", snap[i]);
   printf("\n");
   if (ff == WIN_CHECK / 4) {
      printf("  !! 全是 0xFFFFFFFF → aperture 讀不到這段，停止\n");
      return 1;
   }
   if (diff) {
      printf("  !! 3 秒內有 %u 個 dword 變了（第一個 +0x%x）→ 有人在用這段，不要跑 up\n", diff, firstdiff);
      return 1;
   }
   printf("  3 秒內沒有任何變化 → %s（up 會先清 0）\n", nz ? "是殘留資料，沒人在用" : "全 0，沒人在用");
   return 0;
}

static int cmd_up(int drmkey, const char *fwpath)
{
   if (cmd_check())
      return 1;
   size_t fwlen = 0;
   uint8_t *fw = read_file(fwpath, &fwlen);
   if (!fw || fwlen < 0x100) {
      printf("  !! 讀不到韌體 %s\n", fwpath);
      return 1;
   }
   uint32_t hsize = *(uint32_t *)(fw + 0), ip_major = *(uint16_t *)(fw + 12), ucode_size = *(uint32_t *)(fw + 20),
            ucode_off = *(uint32_t *)(fw + 24);
   printf("== 1. PSP 載 VCN 韌體  %s：size %u ip %u ucode_version 0x%08x ucode_size %u offset 0x%x\n", fwpath, hsize,
          ip_major, *(uint32_t *)(fw + 16), ucode_size, ucode_off);
   if (hsize != fwlen || ip_major != 4 || ucode_off + ucode_size > fwlen) {
      printf("  !! 韌體表頭不對，停止\n");
      return 1;
   }
   if (psp_load(fw + ucode_off, ucode_size, GFX_FW_TYPE_VCN, FWBUF_VCN, "VCN"))
      return 1;

   printf("== 2. SMU PowerUpVcn（VCN 預設斷電）\n");
   if (smu_raw(PPSMC_MSG_PowerUpVcn, 0 << 16, "PowerUpVcn"))
      return 1;
   usleep(10000);
   dump_regs();

   printf("== 3. fw_shared @+0x%x、清空 ring @+0x%x\n", FWSHARED_OFF, RING_OFF);
   struct vcn4_fw_shared fs;
   memset(&fs, 0, sizeof fs);
   fs.present_flag_0 = AMDGPU_FW_SHARED_FLAG_0_UNIFIED_QUEUE | AMDGPU_VCN_SMU_DPM_INTERFACE_FLAG;
   fs.sq.is_enabled = 1;
   fs.smu_dpm_interface.smu_interface_type = AMDGPU_VCN_SMU_DPM_INTERFACE_APU;
   if (drmkey) {
      fs.present_flag_0 |= AMDGPU_FW_SHARED_FLAG_0_DRM_KEY_INJECT;
      fs.drm_key_wa.method = AMDGPU_DRM_KEY_INJECT_WORKAROUND_VCNFW_ASD_HANDSHAKING;
   }
   printf("  present_flag_0 0x%08x%s\n", fs.present_flag_0, drmkey ? "（含 DRM key inject / ASD handshaking）" : "");
   printf("  清 0 VCPU BO（stack + context，%u KiB，跟 Linux amdgpu_vcn_resume 一樣）\n",
          (AMDGPU_VCN_STACK_SIZE + AMDGPU_VCN_CONTEXT_SIZE) >> 10);
   if (vram_zero(VCPU_OFF, AMDGPU_VCN_STACK_SIZE + AMDGPU_VCN_CONTEXT_SIZE) || vram_zero(FWSHARED_OFF, 4096) || vram_write_block(FWSHARED_OFF, &fs, (sizeof fs + 3) & ~3u) ||
       vram_zero(RING_OFF, RING_BYTES))
      return 1;

   printf("== 4. UVD_POWER_STATUS：anti-hang + 動態電源閘控\n");
   uint32_t ps = rreg(R(regUVD_POWER_STATUS));
   wreg_log("UVD_POWER_STATUS", R(regUVD_POWER_STATUS), (ps & ~UVD_POWER_STATUS__UVD_POWER_STATUS_MASK) | 1);
   ps = rreg(R(regUVD_POWER_STATUS)) | UVD_POWER_STATUS__UVD_PG_MODE_MASK | UVD_POWER_STATUS__UVD_PG_EN_MASK;
   wreg_log("UVD_POWER_STATUS", R(regUVD_POWER_STATUS), ps);

   printf("== 5. DPG SRAM 清單（vcn_v4_0_start_dpg_mode，indirect）→ PSP VCN0_RAM\n");
   const uint64_t vcpu_mc = fb_mc_base + VCPU_OFF, fs_mc = fb_mc_base + FWSHARED_OFF;
   nsram = 0;
   /* clock gating：Phoenix 有 AMD_CG_SUPPORT_VCN_MGCG → Linux 直接 return，這裡也不寫 */
   dpg("UVD_VCPU_CNTL (CLK_EN|BLK_RST)", regUVD_VCPU_CNTL,
       (0xFFu << UVD_VCPU_CNTL__PRB_TIMEOUT_VAL__SHIFT) | UVD_VCPU_CNTL__CLK_EN_MASK | UVD_VCPU_CNTL__BLK_RST_MASK);
   dpg("UVD_MASTINT_EN (0)", regUVD_MASTINT_EN, 0);
   dpg("UVD_LMI_CTRL", regUVD_LMI_CTRL,
       UVD_LMI_CTRL__WRITE_CLEAN_TIMER_EN_MASK | UVD_LMI_CTRL__REQ_MODE_MASK | UVD_LMI_CTRL__CRC_RESET_MASK |
           UVD_LMI_CTRL__MASK_MC_URGENT_MASK | UVD_LMI_CTRL__DATA_COHERENCY_EN_MASK |
           UVD_LMI_CTRL__VCPU_DATA_COHERENCY_EN_MASK | (8u << UVD_LMI_CTRL__WRITE_CLEAN_TIMER__SHIFT) | 0x00100000u);
   dpg("UVD_MPC_CNTL", regUVD_MPC_CNTL, 0x2u << UVD_MPC_CNTL__REPLACEMENT_MODE__SHIFT);
   dpg("UVD_MPC_SET_MUXA0", regUVD_MPC_SET_MUXA0, (1u << 6) | (2u << 12) | (3u << 18) | (4u << 24));
   dpg("UVD_MPC_SET_MUXB0", regUVD_MPC_SET_MUXB0, (1u << 6) | (2u << 12) | (3u << 18) | (4u << 24));
   dpg("UVD_MPC_SET_MUX", regUVD_MPC_SET_MUX, (0u << 0) | (1u << 3) | (2u << 6));
   /* mc_resume_dpg_mode（PSP 載入 + indirect：韌體窗口由 PSP 填，寫 0） */
   dpg("LMI_VCPU_CACHE_BAR_LOW (PSP)", regUVD_LMI_VCPU_CACHE_64BIT_BAR_LOW, 0);
   dpg("LMI_VCPU_CACHE_BAR_HIGH (PSP)", regUVD_LMI_VCPU_CACHE_64BIT_BAR_HIGH, 0);
   dpg("VCPU_CACHE_OFFSET0", regUVD_VCPU_CACHE_OFFSET0, 0);
   dpg("VCPU_CACHE_SIZE0 (PSP)", regUVD_VCPU_CACHE_SIZE0, 0);
   dpg("LMI_VCPU_CACHE1_BAR_LOW (PSP)", regUVD_LMI_VCPU_CACHE1_64BIT_BAR_LOW, 0);
   dpg("LMI_VCPU_CACHE1_BAR_HIGH (PSP)", regUVD_LMI_VCPU_CACHE1_64BIT_BAR_HIGH, 0);
   dpg("VCPU_CACHE_OFFSET1", regUVD_VCPU_CACHE_OFFSET1, 0);
   dpg("VCPU_CACHE_SIZE1 (stack)", regUVD_VCPU_CACHE_SIZE1, AMDGPU_VCN_STACK_SIZE);
   dpg("LMI_VCPU_CACHE2_BAR_LOW (context)", regUVD_LMI_VCPU_CACHE2_64BIT_BAR_LOW,
       (uint32_t)(vcpu_mc + AMDGPU_VCN_STACK_SIZE));
   dpg("LMI_VCPU_CACHE2_BAR_HIGH (context)", regUVD_LMI_VCPU_CACHE2_64BIT_BAR_HIGH,
       (uint32_t)((vcpu_mc + AMDGPU_VCN_STACK_SIZE) >> 32));
   dpg("VCPU_CACHE_OFFSET2", regUVD_VCPU_CACHE_OFFSET2, 0);
   dpg("VCPU_CACHE_SIZE2 (context)", regUVD_VCPU_CACHE_SIZE2, AMDGPU_VCN_CONTEXT_SIZE);
   dpg("LMI_VCPU_NC0_BAR_LOW (fw_shared)", regUVD_LMI_VCPU_NC0_64BIT_BAR_LOW, (uint32_t)fs_mc);
   dpg("LMI_VCPU_NC0_BAR_HIGH (fw_shared)", regUVD_LMI_VCPU_NC0_64BIT_BAR_HIGH, (uint32_t)(fs_mc >> 32));
   dpg("VCPU_NONCACHE_OFFSET0", regUVD_VCPU_NONCACHE_OFFSET0, 0);
   dpg("VCPU_NONCACHE_SIZE0", regUVD_VCPU_NONCACHE_SIZE0, (sizeof(struct vcn4_fw_shared) + 4095) & ~4095u);
   dpg("UVD_GFX10_ADDR_CONFIG", regUVD_GFX10_ADDR_CONFIG, GB_ADDR_CONFIG);
   dpg("UVD_VCPU_CNTL (CLK_EN)", regUVD_VCPU_CNTL,
       (0xFFu << UVD_VCPU_CNTL__PRB_TIMEOUT_VAL__SHIFT) | UVD_VCPU_CNTL__CLK_EN_MASK);
   dpg("UVD_LMI_CTRL2", regUVD_LMI_CTRL2, 0x1Fu << UVD_LMI_CTRL2__RE_OFLD_MIF_WR_REQ_NUM__SHIFT);
   /* enable_ras：APU 不支援 VCN RAS，Linux 不寫 */
   dpg("UVD_MASTINT_EN (VCPU_EN)", regUVD_MASTINT_EN, UVD_MASTINT_EN__VCPU_EN_MASK);
   if (psp_load(sram, nsram * 4, GFX_FW_TYPE_VCN0_RAM, FWBUF_SRAM, "VCN0_RAM"))
      return 1;
   dump_regs();

   printf("== 6. unified ring @+0x%x（MC 0x%llx），直接寫 WPTR（不用 doorbell）\n", RING_OFF,
          (unsigned long long)(fb_mc_base + RING_OFF));
   const uint64_t ring_mc = fb_mc_base + RING_OFF;
   wreg_log("UVD_RB_BASE_LO", R(regUVD_RB_BASE_LO), (uint32_t)ring_mc);
   wreg_log("UVD_RB_BASE_HI", R(regUVD_RB_BASE_HI), (uint32_t)(ring_mc >> 32));
   wreg_log("UVD_RB_SIZE", R(regUVD_RB_SIZE), RING_BYTES / 4);
   uint32_t en = rreg(R(regVCN_RB_ENABLE));
   wreg_log("VCN_RB_ENABLE (RB1 off)", R(regVCN_RB_ENABLE), en & ~VCN_RB_ENABLE__RB1_EN_MASK);
   const uint32_t qm_off = FWSHARED_OFF + offsetof(struct vcn4_fw_shared, sq);
   fs.sq.queue_mode |= FW_QUEUE_RING_RESET;
   vram_write(qm_off, *(uint32_t *)&fs.sq);
   wreg_log("UVD_RB_RPTR", R(regUVD_RB_RPTR), 0);
   wreg_log("UVD_RB_WPTR", R(regUVD_RB_WPTR), 0);
   uint32_t rp = rreg(R(regUVD_RB_RPTR));
   wreg_log("UVD_RB_WPTR (= RPTR)", R(regUVD_RB_WPTR), rp);
   en = rreg(R(regVCN_RB_ENABLE));
   wreg_log("VCN_RB_ENABLE (RB1 on)", R(regVCN_RB_ENABLE), en | VCN_RB_ENABLE__RB1_EN_MASK);
   fs.sq.queue_mode &= (uint8_t)~(FW_QUEUE_RING_RESET | FW_QUEUE_DPG_HOLD_OFF);
   vram_write(qm_off, *(uint32_t *)&fs.sq);
   printf("  UVD_STATUS 讀回 0x%08x\n", rreg(R(regUVD_STATUS)));
   dump_regs();
   free(fw);
   printf("== up 完成%s。下一步：vcnctl ringtest\n", failed ? "（有錯誤，看上面的 !!）" : "");
   return failed;
}

static int cmd_ringtest(void)
{
   printf("== ringtest（VCN_ENC_CMD_END + 63 NOP，同 amdgpu_vcn_enc_ring_test_ring）\n");
   uint32_t rptr0 = rreg(R(regUVD_RB_RPTR)), wptr = rreg(R(regUVD_RB_WPTR));
   printf("  開始 RPTR 0x%x WPTR 0x%x\n", rptr0, wptr);
   const uint32_t ndw = RING_BYTES / 4;
   for (uint32_t i = 0; i < 64; i++)
      vram_write(RING_OFF + ((wptr + i) % ndw) * 4, i == 0 ? VCN_ENC_CMD_END : VCN_ENC_CMD_NO_OP);
   uint32_t nw = (wptr + 64) % ndw;
   wreg_log("UVD_RB_WPTR", R(regUVD_RB_WPTR), nw);
   double t0 = now_ms();
   uint32_t r;
   while ((r = rreg(R(regUVD_RB_RPTR))) == rptr0 && now_ms() - t0 < 2000)
      usleep(1000);
   printf("  RPTR 0x%x -> 0x%x（%.0f ms）%s\n", rptr0, r, now_ms() - t0,
          r != rptr0 ? "  ✅ VCN 有在讀 ring" : "  ✗ 2 秒內 RPTR 沒動");
   dump_regs();
   return r == rptr0;
}


/* ---- 階段 2a：IB + fence（照 amdgpu_vcn_dec_sw_ring_test_ib / amdgpu_ib_schedule / amdgpu_ring_commit） ----
   每個 job 在 ring 上是：VCN_ENC_CMD_IB(vmid 0, IB MC 位址, 長度) + VCN_ENC_CMD_FENCE(位址, seq) [+ TRAP] + END + NOP 補到 64 對齊。
   vmid 0 = 不經 page table，直接用 MC 位址；所以 IB、msg、fence 全放在 VRAM 窗口裡（ring test 已證明 VCN 讀得到這段）。
   預設不送 TRAP（nullarc 沒有 IH ring，沒人收 VCN 中斷）；--trap 才送。 */
#define IB_OFF (WIN_OFF + 0x00110000u)      /* 兩個 IB，各 4 KiB */
#define MSG_OFF (WIN_OFF + 0x00120000u)     /* create / destroy msg，各 8 KiB（Linux 用 2 頁、取頁對齊處） */
#define FENCE_OFF (WIN_OFF + 0x00108000u)   /* fence 寫回處（ring 之後） */
#define AMDGPU_VCN_IB_FLAG_DECODE_BUFFER 0x00000001
#define AMDGPU_VCN_CMD_FLAG_MSG_BUFFER 0x00000001
#define VCN_ENC_CMD_IB 0x00000002
#define VCN_ENC_CMD_FENCE 0x00000003
#define VCN_ENC_CMD_TRAP 0x00000004

static void hdp_flush(void)
{
   if (hdp_flush_dword)
      wreg(hdp_flush_dword, 0);
   rreg(0x0DE3); /* 讀回當屏障（GRBM_STATUS），同 kext */
}

/* 組一個 unified-queue 的 decode IB（amdgpu_vcn_dec_sw_send_msg），回傳 length_dw */
static uint32_t build_dec_ib(uint32_t *ib, uint64_t msg_mc)
{
   uint32_t n = 0;
   const uint32_t decbuf_dw = 33; /* struct amdgpu_vcn_decode_buffer：3 + pad[30] */
   const uint32_t pack = decbuf_dw + 4 + 2;
   memset(ib, 0, 72 * 4);
   ib[n++] = 0x00000010; /* single queue checksum */
   ib[n++] = 0x30000002;
   uint32_t ck = n++;
   ib[n++] = pack;
   ib[n++] = 0x00000010; /* engine info */
   ib[n++] = 0x30000001;
   ib[n++] = 0x3; /* decode */
   ib[n++] = pack * 4;
   ib[n++] = decbuf_dw * 4 + 8;
   ib[n++] = AMDGPU_VCN_IB_FLAG_DECODE_BUFFER;
   ib[n + 0] = AMDGPU_VCN_CMD_FLAG_MSG_BUFFER;
   ib[n + 1] = (uint32_t)(msg_mc >> 32);
   ib[n + 2] = (uint32_t)msg_mc;
   n += decbuf_dw;
   uint32_t sum = 0;
   for (uint32_t i = 0; i < pack; i++)
      sum += ib[ck + 2 + i];
   ib[ck] = sum;
   return n;
}

static int submit_job_vm(uint32_t *wptr, uint32_t vmid, uint64_t ib_mc, uint32_t ib_dw, uint64_t fence_mc, uint32_t seq,
                         int trap)
{
   const uint32_t ndw = RING_BYTES / 4;
   uint32_t cmd[16], n = 0;
   cmd[n++] = VCN_ENC_CMD_IB;
   cmd[n++] = vmid;
   cmd[n++] = (uint32_t)ib_mc;
   cmd[n++] = (uint32_t)(ib_mc >> 32);
   cmd[n++] = ib_dw;
   cmd[n++] = VCN_ENC_CMD_FENCE;
   cmd[n++] = (uint32_t)fence_mc;
   cmd[n++] = (uint32_t)(fence_mc >> 32);
   cmd[n++] = seq;
   if (trap)
      cmd[n++] = VCN_ENC_CMD_TRAP;
   cmd[n++] = VCN_ENC_CMD_END;
   uint32_t w = *wptr, total = (n + 63) & ~63u;
   for (uint32_t i = 0; i < total; i++)
      if (vram_write(RING_OFF + ((w + i) % ndw) * 4, i < n ? cmd[i] : VCN_ENC_CMD_NO_OP))
         return 1;
   hdp_flush();
   *wptr = (w + total) % ndw;
   wreg_log("UVD_RB_WPTR", R(regUVD_RB_WPTR), *wptr);
   return 0;
}

static int submit_job(uint32_t *wptr, uint64_t ib_mc, uint32_t ib_dw, uint32_t seq, int trap)
{
   return submit_job_vm(wptr, 0, ib_mc, ib_dw, fb_mc_base + FENCE_OFF, seq, trap);
}

static int wait_fence(uint32_t seq, uint32_t rptr_before)
{
   double t0 = now_ms();
   uint32_t f = 0;
   while (now_ms() - t0 < 2000) {
      if (vram_read(FENCE_OFF, &f, 1))
         return 1;
      if (f == seq)
         break;
      usleep(1000);
   }
   uint32_t rp = rreg(R(regUVD_RB_RPTR));
   printf("  fence = 0x%x（等 0x%x，%.0f ms）RPTR 0x%x -> 0x%x  %s\n", f, seq, now_ms() - t0, rptr_before, rp,
          f == seq ? "✅" : "✗ 逾時");
   return f != seq;
}

static void dump_vram(const char *name, uint32_t off, uint32_t dw)
{
   uint32_t b[32];
   if (dw > 32)
      dw = 32;
   if (vram_read(off, b, dw))
      return;
   printf("  %s +0x%x:", name, off);
   for (uint32_t i = 0; i < dw; i++)
      printf("%s%08x", i % 8 ? " " : "\n    ", b[i]);
   printf("\n");
}

static int cmd_ibtest(int trap)
{
   printf("== ibtest（decode create + destroy msg，同 amdgpu_vcn_dec_sw_ring_test_ib）%s\n", trap ? "  含 TRAP" : "");
   printf("  hdp flush dword 0x%x  IB +0x%x  msg +0x%x  fence +0x%x\n", hdp_flush_dword, IB_OFF, MSG_OFF, FENCE_OFF);
   if (!hdp_flush_dword)
      printf("  （注意：讀不到 phx-hdp-flush-dword，只用讀回當屏障）\n");
   uint32_t rp = rreg(R(regUVD_RB_RPTR)), wp = rreg(R(regUVD_RB_WPTR));
   uint32_t en = rreg(R(regVCN_RB_ENABLE));
   printf("  RPTR 0x%x WPTR 0x%x VCN_RB_ENABLE 0x%x\n", rp, wp, en);
   if (rp != wp || !(en & VCN_RB_ENABLE__RB1_EN_MASK)) {
      printf("  !! ring 沒準備好（要先 up；RPTR 要等於 WPTR）\n");
      return 1;
   }
   if (vram_zero(IB_OFF, 0x2000) || vram_zero(MSG_OFF, 0x4000) || vram_zero(FENCE_OFF, 64))
      return 1;
   /* create msg（amdgpu_vcn_dec_get_create_msg，handle 1） */
   static const uint32_t create[14] = {0x28, 0x38, 0x1, 0x0, 1, 0x0, 0x1, 0x28, 0x10, 0x0, 0x7, 0x0, 0x780, 0x440};
   static const uint32_t destroy[6] = {0x28, 0x18, 0x0, 0x2, 1, 0x0};
   if (vram_write_block(MSG_OFF, create, sizeof create) || vram_write_block(MSG_OFF + 0x2000, destroy, sizeof destroy))
      return 1;
   uint32_t ib[72];
   uint32_t n1 = build_dec_ib(ib, fb_mc_base + MSG_OFF);
   if (vram_write_block(IB_OFF, ib, sizeof ib))
      return 1;
   uint32_t n2 = build_dec_ib(ib, fb_mc_base + MSG_OFF + 0x2000);
   if (vram_write_block(IB_OFF + 0x1000, ib, sizeof ib))
      return 1;
   dump_vram("IB1", IB_OFF, 16);

   printf("-- job 1：create msg（seq 1）\n");
   if (submit_job(&wp, fb_mc_base + IB_OFF, n1, 1, trap))
      return 1;
   int bad = wait_fence(1, rp);
   dump_vram("msg(create)", MSG_OFF, 16);
   if (!bad) {
      printf("-- job 2：destroy msg（seq 2）\n");
      rp = rreg(R(regUVD_RB_RPTR));
      if (submit_job(&wp, fb_mc_base + IB_OFF + 0x1000, n2, 2, trap))
         return 1;
      bad = wait_fence(2, rp);
      dump_vram("msg(destroy)", MSG_OFF + 0x2000, 8);
   }
   dump_regs();
   printf("  %s\n", bad ? "✗ ibtest 失敗" : "✅ ibtest 通過：VCN 執行了 decode IB 並寫回 fence");
   return bad;
}

/* 只讀：MMHUB 3.0.1（seg1 0x1A000）的 VM 狀態。VCN 走 MMHUB、GFX 走 GCHUB；kext 只設了 GC 的 VMID 8..15。
   階段 2b 要把同一份 page table 也掛到 MMHUB 的同一個 VMID，先看現況。 */
#define MMHUB 0x1A000u
static int cmd_mmhub(void)
{
   printf("== mmhub（只讀）\n");
   static const struct { const char *n; uint32_t r; } g[] = {
      {"MMMC_VM_FB_LOCATION_BASE", 0x8ec}, {"MMMC_VM_FB_LOCATION_TOP", 0x8ed}, {"MMMC_VM_AGP_TOP", 0x8ee},
      {"MMMC_VM_AGP_BOT", 0x8ef}, {"MMMC_VM_AGP_BASE", 0x8f0}, {"MMMC_VM_SYSTEM_APERTURE_LOW", 0x8f1},
      {"MMMC_VM_SYSTEM_APERTURE_HIGH", 0x8f2}, {"MMMC_VM_FB_OFFSET", 0x8d7},
      {"MMMC_VM_SYS_APER_DEFAULT_LSB", 0x8d8}, {"MMMC_VM_SYS_APER_DEFAULT_MSB", 0x8d9},
      {"MMMC_VM_MX_L1_TLB_CNTL", 0x8f3}, {"MMVM_L2_CNTL", 0x700}, {"MMVM_L2_CNTL2", 0x701},
      {"MMVM_L2_CNTL3", 0x702}, {"MMVM_L2_CNTL4", 0x718}, {"MMVM_L2_CNTL5", 0x71e},
      {"MMVM_L2_PROT_FAULT_CNTL", 0x708}, {"MMVM_L2_PROT_FAULT_CNTL2", 0x709},
      {"MMVM_L2_PROT_FAULT_STATUS", 0x70c}, {"MMVM_L2_PROT_FAULT_ADDR_LO", 0x70d},
      {"MMVM_L2_PROT_FAULT_ADDR_HI", 0x70e}, {"MMVM_L2_PROT_FAULT_DEF_LO", 0x70f},
      {"MMVM_L2_PROT_FAULT_DEF_HI", 0x710}, {"MMVM_L2_CTX1_IDENT_LOW_LO", 0x712},
      {"MMVM_L2_CTX1_IDENT_LOW_HI", 0x713}, {"MMVM_L2_CTX1_IDENT_HIGH_LO", 0x714},
      {"MMVM_L2_CTX1_IDENT_HIGH_HI", 0x715}, {"MMVM_INV_ENG17_RANGE_LO", 0x787 + 34},
      {"MMVM_INV_ENG17_RANGE_HI", 0x788 + 34}, {"MMVM_INV_ENG17_ACK", 0x775 + 17},
      {"MMVM_CTX0_PT_START_LO", 0x7cb}, {"MMVM_CTX0_PT_START_HI", 0x7cc},
   };
   for (unsigned i = 0; i < sizeof g / sizeof g[0]; i++)
      printf("  %-30s [0x%05x] = 0x%08x\n", g[i].n, MMHUB + g[i].r, rreg(MMHUB + g[i].r));
   for (uint32_t v = 0; v < 16; v++) {
      uint32_t c = rreg(MMHUB + 0x740 + v);
      uint32_t bl = rreg(MMHUB + 0x7ab + 2 * v), bh = rreg(MMHUB + 0x7ab + 2 * v + 1);
      uint32_t el = rreg(MMHUB + 0x7eb + 2 * v), eh = rreg(MMHUB + 0x7eb + 2 * v + 1);
      printf("  MMVM_CONTEXT%-2u CNTL 0x%08x  PT_BASE 0x%08x%08x  END 0x%x%08x\n", v, c, bh, bl, eh, el);
   }
   printf("  對照 GC：L1_TLB_CNTL 0x%08x  L2_CNTL 0x%08x  L2_CNTL3 0x%08x  PROT_FAULT_CNTL 0x%08x\n", rreg(0x1260 + 0x167f),
          rreg(0x1260 + 0x15bc), rreg(0x1260 + 0x15be), rreg(0x1260 + 0x15c4));
   printf("  對照 GC VMID8：CNTL 0x%08x  PT_BASE 0x%08x%08x\n", rreg(0x28E8 + 8), rreg(0x2953 + 17), rreg(0x2953 + 16));
   return failed;
}

/* ---- 階段 2b：MMHUB VM（vmid 1，平面 page table）----
   開機韌體只把 MMHUB 設成「實體模式」：L1_TLB_CNTL 0x501（SYSTEM_ACCESS_MODE 0、沒有 ADVANCED_DRIVER_MODEL）、
   L2 cache 關（L2_CNTL 0x80602）、invalidate range 0、所有 context 停用。這裡照 Linux mmhub_v3_0_1_gart_enable
   把全域設定改成跟 GC 一樣（L1 0x1859、L2 0x80e01、CNTL3 0x80130009、CNTL4 0x1、CNTL5 0x3fe0——都跟 GC 現值相同），
   啟用 MMHUB context 1（depth 0：PDB 直接指向 PTE 陣列，同 mesboot 的 GART context0），
   讓 VCN 用 vmid 1 + 虛擬位址讀 IB/msg、寫 fence（一個在 VRAM、一個在系統記憶體）。結束時全部還原。
   顯示的掃描緩衝在 VRAM（FB aperture 內），SYSTEM_ACCESS_MODE 3 下 vmid 0 的 FB 位址照樣走實體 → 不影響畫面。 */
#define MMR(o) (MMHUB + (o))
#define VM_PT_OFF (WIN_OFF + 0x00180000u)   /* 平面 PTE 表（512 項 = 2 MiB VA） */
#define VM_SCRATCH_OFF (WIN_OFF + 0x001F0000u) /* fault / 系統 aperture 預設頁 */
#define VM_VA 0x0000004000000000ull       /* VA 起點；VA + x 對到 VRAM 窗口 +0xC100000 + x */
#define VM_PAGES 512u
#define VM_SYS_PAGE 511u                    /* 最後一頁改對到系統記憶體 */
#define PTE_VRAM 0x71ull                    /* VALID | EXEC | READ | WRITE（mesboot 的 GART PTE） */
#define PTE_SYS (0x77ull | (4ull << 48))    /* VALID | SYSTEM | SNOOPED | EXEC | READ | WRITE, MTYPE 4（kext kPteSysFlags） */

static const struct { const char *n; uint32_t o; } vm_save_regs[] = {
   {"L1_TLB_CNTL", 0x8f3}, {"L2_CNTL", 0x700}, {"L2_CNTL3", 0x702}, {"L2_CNTL4", 0x718}, {"L2_CNTL5", 0x71e},
   {"PROT_FAULT_CNTL2", 0x709}, {"PROT_FAULT_DEF_LO", 0x70f}, {"PROT_FAULT_DEF_HI", 0x710},
   {"SYS_APER_DEF_LSB", 0x8d8}, {"SYS_APER_DEF_MSB", 0x8d9}, {"INV_ENG17_RANGE_LO", 0x787 + 34},
   {"INV_ENG17_RANGE_HI", 0x788 + 34}, {"CTX1_CNTL", 0x741}, {"CTX1_PT_BASE_LO", 0x7ab + 2},
   {"CTX1_PT_BASE_HI", 0x7ac + 2}, {"CTX1_START_LO", 0x7cb + 2}, {"CTX1_START_HI", 0x7cc + 2},
   {"CTX1_END_LO", 0x7eb + 2}, {"CTX1_END_HI", 0x7ec + 2},
};
#define NVMSAVE (sizeof vm_save_regs / sizeof vm_save_regs[0])

static int sysmem_page(uint64_t *phys)
{
   uint64_t in[3] = {1, 4096, 0}, out[2] = {0, 0};
   uint32_t n = 2;
   kern_return_t kr = IOConnectCallScalarMethod(conn, SEL_DBG_SYSMEM, in, 3, out, &n);
   if (kr) { /* 每次開機只能配一次；已經配過就讀回它的實體位址 */
      uint64_t in2[3] = {2, 0, 0};
      n = 2;
      kr = IOConnectCallScalarMethod(conn, SEL_DBG_SYSMEM, in2, 3, out, &n);
   }
   *phys = out[0];
   return kr || !out[0];
}

static uint32_t sysmem_rw(int write, uint32_t off, uint32_t val)
{
   uint64_t in[3] = {write ? 3u : 2u, off, val}, out[2] = {0, 0};
   uint32_t n = 2;
   if (IOConnectCallScalarMethod(conn, SEL_DBG_SYSMEM, in, 3, out, &n))
      return 0xDEADDEAD;
   return (uint32_t)out[1];
}

static int mm_inv(uint32_t vmid)
{
   wreg(MMR(0x763 + 17), 0x00F80000u | (1u << vmid));
   double t0 = now_ms();
   uint32_t ack;
   while (!((ack = rreg(MMR(0x775 + 17))) & (1u << vmid)) && now_ms() - t0 < 100)
      usleep(100);
   printf("  MMHUB invalidate eng17 vmid %u：ACK 0x%x %s\n", vmid, ack, (ack & (1u << vmid)) ? "OK" : "逾時");
   return !(ack & (1u << vmid));
}

static void mm_fault_dump(void)
{
   printf("  PROT_FAULT_STATUS 0x%08x  ADDR 0x%08x%08x\n", rreg(MMR(0x70c)), rreg(MMR(0x70e)), rreg(MMR(0x70d)));
}

static int cmd_vmtest(int keep)
{
   printf("== vmtest（MMHUB context 1 + VCN 用 vmid 1 的虛擬位址）\n");
   uint32_t rp = rreg(R(regUVD_RB_RPTR)), wp = rreg(R(regUVD_RB_WPTR)), en = rreg(R(regVCN_RB_ENABLE));
   if (rp != wp || !(en & VCN_RB_ENABLE__RB1_EN_MASK)) {
      printf("  !! ring 沒準備好（要先 up）RPTR 0x%x WPTR 0x%x EN 0x%x\n", rp, wp, en);
      return 1;
   }
   const uint64_t fb_pa = (uint64_t)(rreg(MMR(0x8d7)) & 0xFFFFFF) << 24;
   uint64_t sys_pa = 0;
   if (sysmem_page(&sys_pa)) {
      printf("  !! 拿不到系統記憶體頁（SYSMEM selector）\n");
      return 1;
   }
   printf("  FB 實體位址 0x%llx  系統頁 0x%llx  PT +0x%x  VA 0x%llx\n", (unsigned long long)fb_pa,
          (unsigned long long)sys_pa, VM_PT_OFF, (unsigned long long)VM_VA);
   if (fb_pa != 0x7A0000000ull)
      printf("  （注意：FB 實體位址跟 2026-11-22 讀到的 0x7a0000000 不同）\n");

   uint32_t saved[NVMSAVE];
   for (unsigned i = 0; i < NVMSAVE; i++)
      saved[i] = rreg(MMR(vm_save_regs[i].o));
   printf("  備份：");
   for (unsigned i = 0; i < NVMSAVE; i++)
      printf("%s%s=0x%x", i ? " " : "", vm_save_regs[i].n, saved[i]);
   printf("\n");
   mm_fault_dump();

   /* 1. page table：VA 頁 i → VRAM 窗口 +0xC100000 + i*4K；最後一頁 → 系統記憶體 */
   for (uint32_t i = 0; i < VM_PAGES; i++) {
      uint64_t pte = (i == VM_SYS_PAGE) ? ((sys_pa & 0x0000FFFFFFFFF000ull) | PTE_SYS)
                                        : ((fb_pa + RING_OFF + (uint64_t)i * 4096) | PTE_VRAM);
      if (vram_write(VM_PT_OFF + i * 8, (uint32_t)pte) || vram_write(VM_PT_OFF + i * 8 + 4, (uint32_t)(pte >> 32)))
         return 1;
   }
   dump_vram("上次的 scratch 頁（驗證 fence 是否被導到預設頁）", VM_SCRATCH_OFF, 8);
   vram_zero(VM_SCRATCH_OFF, 4096);
   sysmem_rw(1, 0, 0);
   hdp_flush();

   /* 2. 全域：照 Linux（值跟 GC 現值一樣） */
   const uint64_t scratch = (fb_pa + VM_SCRATCH_OFF) >> 12;
   printf("-- MMHUB 全域設定\n");
   wreg_log("SYS_APER_DEFAULT_LSB", MMR(0x8d8), (uint32_t)scratch);
   wreg_log("SYS_APER_DEFAULT_MSB", MMR(0x8d9), (uint32_t)(scratch >> 32));
   wreg_log("PROT_FAULT_DEFAULT_LO", MMR(0x70f), (uint32_t)scratch);
   wreg_log("PROT_FAULT_DEFAULT_HI", MMR(0x710), (uint32_t)(scratch >> 32));
   wreg_log("PROT_FAULT_CNTL2", MMR(0x709), saved[5] | 0x40000);
   wreg_log("MX_L1_TLB_CNTL", MMR(0x8f3), 0x1859);
   wreg_log("L2_CNTL", MMR(0x700), 0x00080e01);
   wreg_log("L2_CNTL2 (invalidate)", MMR(0x701), 0x3);
   wreg_log("L2_CNTL3", MMR(0x702), 0x80130009);
   wreg_log("L2_CNTL4", MMR(0x718), 0x00000001);
   wreg_log("L2_CNTL5", MMR(0x71e), 0x00003fe0);
   wreg_log("INV_ENG17_RANGE_LO", MMR(0x787 + 34), 0xffffffff);
   wreg_log("INV_ENG17_RANGE_HI", MMR(0x788 + 34), 0x1f);

   /* 3. context 1 */
   const uint64_t pdb = fb_pa + VM_PT_OFF;
   const uint64_t vs = VM_VA >> 12, ve = (VM_VA + (uint64_t)VM_PAGES * 4096 - 1) >> 12;
   printf("-- MMHUB context 1（depth 0）\n");
   wreg_log("CTX1_PT_BASE_LO", MMR(0x7ab + 2), (uint32_t)(pdb | 1));
   wreg_log("CTX1_PT_BASE_HI", MMR(0x7ac + 2), (uint32_t)(pdb >> 32));
   wreg_log("CTX1_START_LO", MMR(0x7cb + 2), (uint32_t)vs);
   wreg_log("CTX1_START_HI", MMR(0x7cc + 2), (uint32_t)(vs >> 32));
   wreg_log("CTX1_END_LO", MMR(0x7eb + 2), (uint32_t)ve);
   wreg_log("CTX1_END_HI", MMR(0x7ec + 2), (uint32_t)(ve >> 32));
   wreg_log("CTX1_CNTL", MMR(0x741), 0x01fffe01);
   int bad = mm_inv(1);

   /* 4. 送 job。第一次實測（13:08）：job 用 VA 當 fence 位址 → RPTR 有動、fence 沒寫、也沒有 fault。
      原因：FENCE 指令是 ring 自己的命令，位址照 ring 的 vmid 0 解讀（Linux 的 fence 也是核心 GART/MC 位址），
      只有 IB 的內容才用 IB 指令帶的 vmid。所以 fence 一律用 MC 位址；改用「IB 放哪裡」來驗證 vmid 1 的轉換：
        job 1：IB 在 VRAM（經 VA）、msg 經 VA
        job 2：IB 在系統記憶體（經 VA 最後一頁，PTE SYSTEM|SNOOPED）
        job 3（對照組）：IB 在 page table 範圍外的 VA → 應該看到 PROT_FAULT_STATUS 有記錄 */
   if (!bad) {
      static const uint32_t create[14] = {0x28, 0x38, 0x1, 0x0, 2, 0x0, 0x1, 0x28, 0x10, 0x0, 0x7, 0x0, 0x780, 0x440};
      static const uint32_t destroy[6] = {0x28, 0x18, 0x0, 0x2, 2, 0x0};
      const uint64_t va_ib = VM_VA + (IB_OFF - RING_OFF), va_msg = VM_VA + (MSG_OFF - RING_OFF);
      const uint64_t va_sys = VM_VA + (uint64_t)VM_SYS_PAGE * 4096, fence_mc = fb_mc_base + FENCE_OFF;
      uint32_t ib[72];
      vram_zero(IB_OFF, 0x2000);
      vram_zero(MSG_OFF, 0x4000);
      vram_zero(FENCE_OFF, 64);
      vram_write_block(MSG_OFF, create, sizeof create);
      vram_write_block(MSG_OFF + 0x2000, destroy, sizeof destroy);
      uint32_t n1 = build_dec_ib(ib, va_msg);
      vram_write_block(IB_OFF, ib, sizeof ib);
      uint32_t n2 = build_dec_ib(ib, va_msg + 0x2000);
      for (uint32_t i = 0; i < 72; i++) /* job 2 的 IB 寫進系統記憶體頁 */
         sysmem_rw(1, i * 4, ib[i]);
      uint32_t chk = sysmem_rw(0, 8, 0);
      printf("  系統頁 IB 寫入確認：dword2 = 0x%x（應是 0x%x）\n", chk, ib[2]);
      hdp_flush();

      printf("-- job 1：vmid 1，IB VA 0x%llx（VRAM），msg VA 0x%llx，fence MC seq 0x11\n", (unsigned long long)va_ib,
             (unsigned long long)va_msg);
      bad = submit_job_vm(&wp, 1, va_ib, n1, fence_mc, 0x11, 0) || wait_fence(0x11, rp);
      mm_fault_dump();
      if (!bad) {
         printf("-- job 2：vmid 1，IB VA 0x%llx（系統記憶體 0x%llx），fence MC seq 0x22\n", (unsigned long long)va_sys,
                (unsigned long long)sys_pa);
         rp = rreg(R(regUVD_RB_RPTR));
         bad = submit_job_vm(&wp, 1, va_sys, n2, fence_mc, 0x22, 0) || wait_fence(0x22, rp);
         mm_fault_dump();
      }
      printf("-- job 3（對照組）：vmid 1，IB 在範圍外 VA 0x%llx，fence MC seq 0x33\n",
             (unsigned long long)(VM_VA + 0x10000000ull));
      rp = rreg(R(regUVD_RB_RPTR));
      uint32_t fs0 = rreg(MMR(0x70c));
      if (!submit_job_vm(&wp, 1, VM_VA + 0x10000000ull, n1, fence_mc, 0x33, 0))
         wait_fence(0x33, rp);
      uint32_t fs1 = rreg(MMR(0x70c));
      mm_fault_dump();
      printf("  對照組：PROT_FAULT_STATUS 0x%x -> 0x%x  %s\n", fs0, fs1,
             fs1 != fs0 ? "有記錄 fault → 轉換路徑確實在作用" : "沒有記錄（fault 可能被導到預設頁而不記錄）");
   }

   /* 5. 還原 */
   if (keep) {
      printf("-- --keep：MMHUB 設定保留\n");
   } else {
      printf("-- 還原 MMHUB\n");
      for (int i = (int)NVMSAVE - 1; i >= 0; i--)
         wreg(MMR(vm_save_regs[i].o), saved[i]);
      wreg(MMR(0x701), 0x3);
      int diff = 0;
      for (unsigned i = 0; i < NVMSAVE; i++)
         if (rreg(MMR(vm_save_regs[i].o)) != saved[i]) {
            printf("  !! %s 讀回 0x%x，原本 0x%x\n", vm_save_regs[i].n, rreg(MMR(vm_save_regs[i].o)), saved[i]);
            diff = 1;
         }
      printf("  %s\n", diff ? "有暫存器沒還原成功（見上）" : "全部還原");
   }
   printf("  %s\n", bad ? "✗ vmtest 失敗" : "✅ vmtest 通過：VCN 透過 MMHUB page table（vmid 1）從 VRAM 和系統記憶體讀 IB");
   return bad;
}

static int cmd_down(void)
{
   printf("== down（vcn_v4_0_stop_dpg_mode 簡化版 + PowerDownVcn）\n");
   double t0 = now_ms();
   uint32_t ps;
   while (((ps = rreg(R(regUVD_POWER_STATUS))) & UVD_POWER_STATUS__UVD_POWER_STATUS_MASK) != 1 && now_ms() - t0 < 1000)
      usleep(1000);
   printf("  UVD_POWER_STATUS 0x%08x（等 =1：%s）\n", ps, (ps & 3) == 1 ? "OK" : "逾時，照樣繼續");
   uint32_t en = rreg(R(regVCN_RB_ENABLE));
   wreg_log("VCN_RB_ENABLE (RB1 off)", R(regVCN_RB_ENABLE), en & ~VCN_RB_ENABLE__RB1_EN_MASK);
   ps = rreg(R(regUVD_POWER_STATUS));
   wreg_log("UVD_POWER_STATUS (PG_MODE off)", R(regUVD_POWER_STATUS), ps & ~UVD_POWER_STATUS__UVD_PG_MODE_MASK);
   rreg(R(regUVD_STATUS));
   return smu_raw(PPSMC_MSG_PowerDownVcn, 0 << 16, "PowerDownVcn") ? 1 : failed;
}

int main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IOLBF, 0);
   if (argc < 2) {
      fprintf(stderr, "用法：vcnctl check | up [--no-drmkey] [--fw <vcn_4_0_2.bin>] | regs | ringtest | ibtest [--trap] | vmtest [--keep] | mmhub | down\n");
      return 2;
   }
   if (geteuid() != 0) {
      fprintf(stderr, "請用 sudo 執行\n");
      return 2;
   }
   if (open_kext())
      return 1;
   const char *fw = "/Users/kaoru/fw13-hackintosh/vcn/fw/vcn_4_0_2.bin";
   int drmkey = 1, trap = 0, keep = 0;
   for (int i = 2; i < argc; i++) {
      if (!strcmp(argv[i], "--no-drmkey"))
         drmkey = 0;
      else if (!strcmp(argv[i], "--trap"))
         trap = 1;
      else if (!strcmp(argv[i], "--keep"))
         keep = 1;
      else if (!strcmp(argv[i], "--fw") && i + 1 < argc)
         fw = argv[++i];
   }
   if (!strcmp(argv[1], "check"))
      return cmd_check();
   if (!strcmp(argv[1], "up"))
      return cmd_up(drmkey, fw);
   if (!strcmp(argv[1], "regs")) {
      dump_regs();
      return failed;
   }
   if (!strcmp(argv[1], "ringtest"))
      return cmd_ringtest();
   if (!strcmp(argv[1], "vmtest"))
      return cmd_vmtest(keep);
   if (!strcmp(argv[1], "mmhub"))
      return cmd_mmhub();
   if (!strcmp(argv[1], "ibtest"))
      return cmd_ibtest(trap);
   if (!strcmp(argv[1], "down"))
      return cmd_down();
   fprintf(stderr, "不認得的指令 %s\n", argv[1]);
   return 2;
}
