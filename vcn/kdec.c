// SPDX-License-Identifier: Apache-2.0
// 用 PhxBringup 的 PHXN_SEL_FW13_VCN_DEC（kext 補丁 phxbringup-v040-02）解一個 H.264 檔，不需要 root、不需要 phxdebug。
// 前提：VCN 已經由 root 的 `vcnctl up` 帶起來（ring 在 VRAM +0xC100000）。
// 每張畫面讀回 NV12 算 MD5，排成顯示順序後跟 .framemd5（ffmpeg -f framemd5 -pix_fmt nv12）比對；印出 VCN 時間與整體時間。
//
// clang -O2 -Wall -framework IOKit -framework CoreFoundation vcn/kdec.c vcn/h264/h264_parse.c vcn/h264/vcn_h264_msg.c \
//   vcn/h264/h264_dpb.c vcn/h264/h264_stream.c vcn/h264/md5.c -o vcn/kdec
// 用法：vcn/kdec <檔.h264> [<檔.framemd5>] [--loops N]
#include <IOKit/IOKitLib.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "h264/h264_dpb.h"
#include "h264/h264_parse.h"
#include "h264/h264_stream.h"
#include "h264/md5.h"
#include "h264/vcn_h264_msg.h"

#define UC_TYPE 0x4E34384Eu   // 'N48N'
#define SEL_HELLO 0
#define SEL_FW13_VCN_DEC 130
#define FW13_VCN_MAGIC 0x44333146u

typedef struct {
   uint32_t magic, handle, msg_len, its_len, bs_len, dpb_size, ctx_size, dt_size, reserved[8];
} fw13_hdr;

static io_connect_t conn;
static const char *st_name[] = {"OK", "NOT_UP（VCN 沒帶起來：先 sudo vcnctl up）", "BUSY", "TIMEOUT", "LAYOUT", "NO_SESSION"};

static double now_ms(void)
{
   static mach_timebase_info_data_t tb;
   if (!tb.denom)
      mach_timebase_info(&tb);
   return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

static uint8_t inbuf[(4u << 20) + 65536];

// 回傳 kext 的狀態；kr 錯誤時回傳 -1
static int dec_call(int op, const fw13_hdr *h, const void *msg, const void *its, const void *bs, void *out, uint32_t outlen,
                    uint64_t res[4])
{
   size_t n = 0;
   memcpy(inbuf, h, sizeof *h);
   n += sizeof *h;
   memcpy(inbuf + n, msg, h->msg_len);
   n += h->msg_len;
   if (h->its_len)
      memcpy(inbuf + n, its, h->its_len);
   n += h->its_len;
   if (h->bs_len)
      memcpy(inbuf + n, bs, h->bs_len);
   n += h->bs_len;
   uint64_t in[5] = {(uint64_t)op, (uint64_t)(uintptr_t)inbuf, n, (uint64_t)(uintptr_t)out, outlen};
   uint32_t cnt = 4;
   kern_return_t kr = IOConnectCallScalarMethod(conn, SEL_FW13_VCN_DEC, in, 5, res, &cnt);
   if (kr) {
      fprintf(stderr, "  !! selector %d op %d：kr 0x%08x\n", SEL_FW13_VCN_DEC, op, kr);
      return -1;
   }
   return (int)res[0];
}

typedef struct { uint32_t group; int32_t poc; int idx; uint8_t md5[16]; } frame;
static int cmp_frame(const void *a, const void *b)
{
   const frame *x = a, *y = b;
   if (x->group != y->group) return x->group < y->group ? -1 : 1;
   return x->poc < y->poc ? -1 : x->poc > y->poc;
}

int main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IOLBF, 0);
   if (argc < 2) {
      fprintf(stderr, "用法：%s <檔.h264> [<檔.framemd5>] [--loops N]\n", argv[0]);
      return 2;
   }
   const char *path = argv[1], *md5path = NULL;
   int loops = 1;
   for (int i = 2; i < argc; i++) {
      if (!strcmp(argv[i], "--loops") && i + 1 < argc)
         loops = atoi(argv[++i]);
      else
         md5path = argv[i];
   }
   io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("PhxBringup"));
   if (!svc || IOServiceOpen(svc, mach_task_self(), UC_TYPE, &conn)) {
      fprintf(stderr, "打不開 PhxBringup\n");
      return 1;
   }
   IOObjectRelease(svc);
   uint64_t hin[2] = {1, 0}, hout[4];
   uint32_t hn = 4;
   if (IOConnectCallScalarMethod(conn, SEL_HELLO, hin, 2, hout, &hn)) {
      fprintf(stderr, "Hello 失敗\n");
      return 1;
   }
   printf("== PhxBringup build %llu（FW13 VCN 解碼介面要 134 以上）\n", (unsigned long long)hout[1]);
   if (hout[1] < 134) {
      fprintf(stderr, "kext 太舊，還沒有 PHXN_SEL_FW13_VCN_DEC\n");
      return 1;
   }

   FILE *f = fopen(path, "rb");
   if (!f) {
      fprintf(stderr, "讀不到 %s\n", path);
      return 1;
   }
   fseek(f, 0, SEEK_END);
   long size = ftell(f);
   fseek(f, 0, SEEK_SET);
   uint8_t *buf = malloc((size_t)size);
   if (!buf || fread(buf, 1, (size_t)size, f) != (size_t)size)
      return 1;
   fclose(f);

   static h264_stream st;
   static uint8_t bs[4u << 20];
   h264_picture p;
   h264_stream_init(&st, buf, (size_t)size);
   if (h264_stream_next(&st, &p, bs, sizeof bs) != 1) {
      fprintf(stderr, "串流解析失敗\n");
      return 1;
   }
   const h264_sps *sps = &st.ps.sps[st.ps.pps[p.first.pps_id].sps_id];
   vcn_h264_layout l;
   vcn_h264_layout_init(&l, sps);
   const uint32_t cw = l.width - 2 * (sps->crop_left + sps->crop_right), ch = l.height - 2 * (sps->crop_top + sps->crop_bottom);
   printf("== %s：%ux%u（顯示 %ux%u）dpb %u ctx %u dt %u\n", path, l.width, l.height, cw, ch, l.dpb_size, l.hw_ctx_size, l.dt_size);

   fw13_hdr h = {FW13_VCN_MAGIC, 0x46773134u, 0, 0, 0, l.dpb_size, l.hw_ctx_size, l.dt_size, {0}};
   uint8_t *px = malloc(l.dt_size);
   static frame frames[4096];
   int total_ok = 1;
   for (int loop = 0; loop < loops; loop++) {
      uint32_t w[14];
      uint64_t res[4];
      h.msg_len = vcn_h264_session_msg(w, 0, h.handle, &l) * 4;
      h.its_len = h.bs_len = 0;
      int r = dec_call(1, &h, w, NULL, NULL, NULL, 0, res);
      if (r) {
         printf("  ✗ 建立 session：%s\n", r < 0 ? "kr 錯誤" : st_name[r]);
         return 1;
      }
      h264_dpb dpb;
      h264_dpb_init(&dpb, l.max_num_ref);
      h264_stream_init(&st, buf, (size_t)size);
      int n = 0;
      double vcn_us = 0, t0 = now_ms();
      while (n < 4096 && h264_stream_next(&st, &p, bs, sizeof bs) == 1) {
         vcn_h264_pic pic;
         h264_out_info oi;
         if (h264_dpb_begin(&dpb, sps, &p.first, &pic, &oi)) {
            printf("  ✗ 第 %d 張 DPB 錯誤\n", n);
            total_ok = 0;
            break;
         }
         static uint8_t msg[4096];
         rvcn_dec_avc_its_t its;
         h.msg_len = vcn_h264_decode_msg(msg, &its, h.handle, &l, sps, &st.ps.pps[p.first.pps_id], &p.first, &pic, p.bsd);
         h.its_len = sizeof its;
         h.bs_len = p.bsd;
         r = dec_call(2, &h, msg, &its, bs, px, l.dt_size, res);
         if (r) {
            printf("  ✗ 第 %d 張：%s\n", n, r < 0 ? "kr 錯誤" : st_name[r]);
            total_ok = 0;
            break;
         }
         vcn_us += (double)res[2];
         if (n == 0 && loop == 0)
            printf("  讀回路徑：%s\n", (res[3] & 0x80000000ull) ? "carve-out 系統記憶體（快）" : "BAR（慢）");
         md5_ctx c;
         md5_init(&c);
         const uint32_t x0 = 2 * sps->crop_left, y0 = 2 * sps->crop_top;
         for (uint32_t y = 0; y < ch; y++)
            md5_update(&c, px + (y0 + y) * l.dt_pitch + x0, cw);
         const uint8_t *uv = px + l.dt_pitch * l.dt_height;
         for (uint32_t y = 0; y < ch / 2; y++)
            md5_update(&c, uv + (y0 / 2 + y) * l.dt_pitch + x0, cw);
         md5_final(&c, frames[n].md5);
         frames[n].group = oi.group;
         frames[n].poc = oi.poc;
         frames[n].idx = n;
         h264_dpb_end(&dpb, sps, &p.first, &pic);
         n++;
      }
      double wall = now_ms() - t0;
      h.msg_len = vcn_h264_session_msg(w, 1, h.handle, &l) * 4;
      h.its_len = h.bs_len = 0;
      r = dec_call(3, &h, w, NULL, NULL, NULL, 0, res);
      if (r)
         printf("  ✗ 關閉 session：%s\n", r < 0 ? "kr 錯誤" : st_name[r]);
      printf("  第 %d 輪：%d 張，VCN 平均 %.2f ms／張，整體（含搬資料、讀回、MD5）平均 %.2f ms／張（%.0f fps）\n", loop + 1, n,
             n ? vcn_us / n / 1000 : 0, n ? wall / n : 0, n ? 1000.0 * n / wall : 0);
      if (md5path && loop == 0) {
         FILE *fm = fopen(md5path, "r");
         if (!fm) {
            printf("  ✗ 讀不到 %s\n", md5path);
            total_ok = 0;
            continue;
         }
         qsort(frames, n, sizeof *frames, cmp_frame);
         char line[512];
         int k = 0, bad = 0;
         while (fgets(line, sizeof line, fm)) {
            if (line[0] == '#')
               continue;
            char *hex = strrchr(line, ' ');
            if (!hex || k >= n)
               continue;
            char ours[33];
            for (int i = 0; i < 16; i++)
               snprintf(ours + 2 * i, 3, "%02x", frames[k].md5[i]);
            if (strncmp(ours, hex + 1, 32)) {
               if (bad < 5)
                  printf("  ✗ 顯示第 %d 張（解碼第 %d 張）MD5 不同\n", k, frames[k].idx);
               bad++;
            }
            k++;
         }
         fclose(fm);
         printf("  MD5 比對：%d 張中 %d 張相同\n", k, k - bad);
         if (bad || k != n)
            total_ok = 0;
      }
   }
   printf("%s\n", total_ok ? "✅ kdec 通過" : "✗ kdec 失敗");
   return !total_ok;
}
