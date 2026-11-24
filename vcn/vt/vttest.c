// SPDX-License-Identifier: Apache-2.0
// 用 VideoToolbox（系統的 VTDecompressionSession）解一個 Annex B H.264 檔，看系統挑哪個解碼器、結果對不對。
//   --hw：要求硬體解碼器（kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder）；裝了 H264VCNDecoder 才會成功
//   --sw：關掉硬體（EnableHardwareAcceleratedVideoDecoder = false），當對照組
//   --temporal：送 kVTDecodeFrame_EnableTemporalProcessing（要求依顯示順序輸出）
// 每張輸出算 MD5（裁切後 NV12），依 PTS（＝顯示順序，用 h264_dpb 算的 POC 排出來）跟 .framemd5 比對。
// 用法：vttest <檔.h264> [<檔.framemd5>] [--hw|--sw] [--temporal]
#include <CoreMedia/CoreMedia.h>
#include <CoreVideo/CoreVideo.h>
#include <VideoToolbox/VideoToolbox.h>
#include <mach/mach_time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../h264/h264_dpb.h"
#include "../h264/h264_stream.h"
#include "../h264/md5.h"

#define MAXF 4096
typedef struct { uint32_t group; int32_t poc; int idx; } ord;
static int cmp_ord(const void *a, const void *b)
{
   const ord *x = a, *y = b;
   if (x->group != y->group) return x->group < y->group ? -1 : 1;
   return x->poc < y->poc ? -1 : x->poc > y->poc;
}

static uint8_t g_md5[MAXF][16];
static int g_have[MAXF], g_outorder[MAXF], g_nout, g_errors;
static OSStatus g_firsterr;

static void cb(void *ref, void *src, OSStatus st, VTDecodeInfoFlags flags, CVImageBufferRef img, CMTime pts, CMTime dur)
{
   (void)ref; (void)src; (void)flags; (void)dur;
   if (st || !img) {
      if (!g_firsterr) g_firsterr = st;
      g_errors++;
      return;
   }
   int i = (int)pts.value;
   if (i < 0 || i >= MAXF) return;
   CVPixelBufferLockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
   size_t w = CVPixelBufferGetWidth(img), h = CVPixelBufferGetHeight(img);
   md5_ctx c;
   md5_init(&c);
   const uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(img, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(img, 1);
   size_t ys = CVPixelBufferGetBytesPerRowOfPlane(img, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(img, 1);
   for (size_t r = 0; r < h; r++) md5_update(&c, y + r * ys, w);
   for (size_t r = 0; r < h / 2; r++) md5_update(&c, uv + r * uvs, w);
   CVPixelBufferUnlockBaseAddress(img, kCVPixelBufferLock_ReadOnly);
   md5_final(&c, g_md5[i]);
   g_have[i] = 1;
   if (g_nout < MAXF) g_outorder[g_nout++] = i;
}

static double now_ms(void)
{
   static mach_timebase_info_data_t tb;
   if (!tb.denom) mach_timebase_info(&tb);
   return (double)mach_absolute_time() * tb.numer / tb.denom / 1e6;
}

int main(int argc, char **argv)
{
   setvbuf(stdout, NULL, _IOLBF, 0);
   if (argc < 2) {
      fprintf(stderr, "用法：%s <檔.h264> [<檔.framemd5>] [--hw|--sw] [--temporal]\n", argv[0]);
      return 2;
   }
   const char *path = argv[1], *md5path = NULL;
   int hw = 0, sw = 0, temporal = 0;
   for (int i = 2; i < argc; i++) {
      if (!strcmp(argv[i], "--hw")) hw = 1;
      else if (!strcmp(argv[i], "--sw")) sw = 1;
      else if (!strcmp(argv[i], "--temporal")) temporal = 1;
      else md5path = argv[i];
   }
   FILE *f = fopen(path, "rb");
   if (!f) return 1;
   fseek(f, 0, SEEK_END);
   long size = ftell(f);
   fseek(f, 0, SEEK_SET);
   uint8_t *buf = malloc((size_t)size);
   if (!buf || fread(buf, 1, (size_t)size, f) != (size_t)size) return 1;
   fclose(f);

   // 1. 第一個 SPS／PPS → 格式描述
   const uint8_t *sps = NULL, *pps = NULL;
   size_t spsl = 0, ppsl = 0, pos = 0, len;
   const uint8_t *nal;
   while ((nal = h264_next_nal(buf, (size_t)size, &pos, &len))) {
      if ((nal[0] & 31) == 7 && !sps) { sps = nal; spsl = len; }
      if ((nal[0] & 31) == 8 && !pps) { pps = nal; ppsl = len; }
   }
   if (!sps || !pps) { fprintf(stderr, "沒有 SPS／PPS\n"); return 1; }
   const uint8_t *ps[2] = {sps, pps};
   size_t psl[2] = {spsl, ppsl};
   CMVideoFormatDescriptionRef fmt = NULL;
   if (CMVideoFormatDescriptionCreateFromH264ParameterSets(NULL, 2, ps, psl, 4, &fmt)) { fprintf(stderr, "格式描述失敗\n"); return 1; }

   // 2. 先跑一次 parser＋DPB：每張畫面的顯示順序（PTS）
   static h264_stream st;
   static uint8_t bs[4u << 20];
   static ord o[MAXF];
   h264_stream_init(&st, buf, (size_t)size);
   h264_picture p;
   h264_dpb dpb;
   int n = 0;
   while (n < MAXF && h264_stream_next(&st, &p, bs, sizeof bs) == 1) {
      const h264_sps *s = &st.ps.sps[st.ps.pps[p.first.pps_id].sps_id];
      if (!n) {
         vcn_h264_layout l;
         vcn_h264_layout_init(&l, s);
         h264_dpb_init(&dpb, l.max_num_ref);
      }
      vcn_h264_pic pic;
      h264_out_info oi;
      if (h264_dpb_begin(&dpb, s, &p.first, &pic, &oi)) break;
      o[n].group = oi.group; o[n].poc = oi.poc; o[n].idx = n;
      h264_dpb_end(&dpb, s, &p.first, &pic);
      n++;
   }
   static int disp[MAXF];
   qsort(o, n, sizeof *o, cmp_ord);
   for (int i = 0; i < n; i++) disp[o[i].idx] = i;

   // 3. session
   CFMutableDictionaryRef spec = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
   if (hw) CFDictionarySetValue(spec, kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder, kCFBooleanTrue);
   if (sw) CFDictionarySetValue(spec, kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder, kCFBooleanFalse);
   int32_t pf = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
   CFNumberRef pfn = CFNumberCreate(NULL, kCFNumberSInt32Type, &pf);
   const void *ak[] = {kCVPixelBufferPixelFormatTypeKey};
   const void *av[] = {pfn};
   CFDictionaryRef attrs = CFDictionaryCreate(NULL, ak, av, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
   VTDecompressionOutputCallbackRecord rec = {cb, NULL};
   VTDecompressionSessionRef sess = NULL;
   OSStatus r = VTDecompressionSessionCreate(NULL, fmt, spec, attrs, &rec, &sess);
   printf("== %s：%d 張，模式 %s%s，VTDecompressionSessionCreate = %d\n", path, n, hw ? "要求硬體" : sw ? "只用軟體" : "系統預設",
          temporal ? "、顯示順序輸出" : "", (int)r);
   if (r) {
      printf("  ✗ 建立 session 失敗（-12906 = 找不到符合的解碼器）\n");
      return 1;
   }
   CFBooleanRef usinghw = NULL;
   VTSessionCopyProperty(sess, kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder, NULL, &usinghw);
   printf("  UsingHardwareAcceleratedVideoDecoder = %s\n", usinghw == kCFBooleanTrue ? "true" : "false");

   // 4. 送 sample（AVCC，4-byte 長度）
   h264_stream_init(&st, buf, (size_t)size);
   static uint8_t avcc[4u << 20];
   int k = 0;
   double t0 = now_ms();
   while (k < n && h264_stream_next(&st, &p, bs, sizeof bs) == 1) {
      size_t m = 0, q = 0, l2;
      const uint8_t *x;
      while ((x = h264_next_nal(bs, p.bsd, &q, &l2))) {
         avcc[m++] = (uint8_t)(l2 >> 24); avcc[m++] = (uint8_t)(l2 >> 16); avcc[m++] = (uint8_t)(l2 >> 8); avcc[m++] = (uint8_t)l2;
         memcpy(avcc + m, x, l2);
         m += l2;
      }
      CMBlockBufferRef bb = NULL;
      CMBlockBufferCreateWithMemoryBlock(NULL, NULL, m, NULL, NULL, 0, m, kCMBlockBufferAssureMemoryNowFlag, &bb);
      CMBlockBufferReplaceDataBytes(avcc, bb, 0, m);
      CMSampleTimingInfo ti = {CMTimeMake(1, 30), CMTimeMake(disp[k], 30), CMTimeMake(k, 30)};
      CMSampleBufferRef sb = NULL;
      CMSampleBufferCreateReady(NULL, bb, fmt, 1, 1, &ti, 1, &m, &sb);
      VTDecodeFrameFlags fl = kVTDecodeFrame_EnableAsynchronousDecompression | (temporal ? kVTDecodeFrame_EnableTemporalProcessing : 0);
      VTDecodeInfoFlags info = 0;
      OSStatus dr = VTDecompressionSessionDecodeFrame(sess, sb, fl, NULL, &info);
      if (dr && !g_firsterr) g_firsterr = dr;
      CFRelease(sb);
      CFRelease(bb);
      k++;
   }
   VTDecompressionSessionFinishDelayedFrames(sess);
   VTDecompressionSessionWaitForAsynchronousFrames(sess);
   double wall = now_ms() - t0;
   int inorder = 1;
   for (int i = 1; i < g_nout; i++) inorder &= g_outorder[i] > g_outorder[i - 1];
   printf("  輸出 %d 張、錯誤 %d（第一個 %d），每張 %.2f ms；輸出順序%s\n", g_nout, g_errors, (int)g_firsterr, n ? wall / n : 0,
          inorder ? "＝顯示順序" : "≠ 顯示順序（解碼順序或其他）");
   int ok = g_nout == n && !g_errors;
   if (md5path) {
      FILE *fm = fopen(md5path, "r");
      char line[512];
      int i = 0, bad = 0;
      while (fm && fgets(line, sizeof line, fm)) {
         if (line[0] == '#') continue;
         char *hex = strrchr(line, ' ');
         if (!hex || i >= n) continue;
         char ours[33] = "";
         for (int j = 0; j < 16; j++) snprintf(ours + 2 * j, 3, "%02x", g_md5[i][j]);
         if (!g_have[i] || strncmp(ours, hex + 1, 32)) bad++;
         i++;
      }
      if (fm) fclose(fm);
      printf("  MD5 比對：%d 張中 %d 張相同\n", i, i - bad);
      ok = ok && !bad && i == n;
   }
   VTDecompressionSessionInvalidate(sess);
   CFRelease(sess);
   printf("%s\n", ok ? "✅ vttest 通過" : "✗ vttest 失敗");
   return !ok;
}
