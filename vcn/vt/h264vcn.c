// SPDX-License-Identifier: Apache-2.0
// 見 h264vcn.h。kext 介面同 vcn/kdec.c（已在 FW13 上驗證 t1–t5 bit-exact）。
#include "h264vcn.h"

#include <IOKit/IOKitLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../h264/h264_dpb.h"
#include "../h264/h264_parse.h"
#include "../h264/vcn_h264_msg.h"

#define UC_TYPE 0x4E34384Eu   // 'N48N'
#define SEL_HELLO 0
#define SEL_FW13_VCN_DEC 130
#define FW13_VCN_MAGIC 0x44333146u
#define MIN_KEXT_BUILD 135u
#define BS_CAP (4u << 20)

typedef struct {
   uint32_t magic, handle, msg_len, its_len, bs_len, dpb_size, ctx_size, dt_size, reserved[8];
} fw13_hdr;

struct H264Vcn {
   io_connect_t conn;
   int session_open;
   h264_params ps;
   int sps_id;
   h264_dpb dpb;
   vcn_h264_layout l;
   uint32_t handle;
   int nal_len;
   uint32_t cw, ch, x0, y0;
   uint8_t *inbuf, *bs, *out;
   CVPixelBufferPoolRef pool;
   uint32_t vcn_us;
   char err[256];
};

static void seterr(H264Vcn *v, const char *m) { snprintf(v->err, sizeof v->err, "%s", m); }
const char *h264vcn_last_error(const H264Vcn *v) { return v->err; }
uint32_t h264vcn_last_vcn_us(const H264Vcn *v) { return v->vcn_us; }
void h264vcn_size(const H264Vcn *v, int32_t *w, int32_t *h)
{
   *w = (int32_t)v->cw;
   *h = (int32_t)v->ch;
}

// 回傳 kext 狀態（PHXN_FW13_VCN_*），kr 錯誤回 -1
static int kcall(H264Vcn *v, int op, uint32_t msg_len, const void *msg, uint32_t its_len, const void *its, uint32_t bs_len,
                 void *out, uint32_t outlen, uint64_t res[4])
{
   fw13_hdr h = {FW13_VCN_MAGIC, v->handle, msg_len, its_len, bs_len, v->l.dpb_size, v->l.hw_ctx_size, v->l.dt_size, {0}};
   size_t n = 0;
   memcpy(v->inbuf, &h, sizeof h);
   n += sizeof h;
   memcpy(v->inbuf + n, msg, msg_len);
   n += msg_len;
   if (its_len) memcpy(v->inbuf + n, its, its_len);
   n += its_len;
   if (bs_len) memcpy(v->inbuf + n, v->bs, bs_len);
   n += bs_len;
   uint64_t in[5] = {(uint64_t)op, (uint64_t)(uintptr_t)v->inbuf, n, (uint64_t)(uintptr_t)out, outlen};
   uint32_t cnt = 4;
   if (IOConnectCallScalarMethod(v->conn, SEL_FW13_VCN_DEC, in, 5, res, &cnt))
      return -1;
   return (int)res[0];
}

static uint32_t g_handles;

H264Vcn *h264vcn_create(const uint8_t *c, size_t len, int *why, char *msg, size_t msglen)
{
   *why = H264VCN_UNSUPPORTED;
   H264Vcn *v = calloc(1, sizeof *v);
   if (!v) {
      *why = H264VCN_MEMORY;
      return NULL;
   }
   v->conn = IO_OBJECT_NULL;
   v->sps_id = -1;
#define FAIL(code, text) do { *why = (code); snprintf(msg, msglen, "%s", text); h264vcn_destroy(v); return NULL; } while (0)
   // avcC
   if (!c || len < 7 || c[0] != 1)
      FAIL(H264VCN_UNSUPPORTED, "avcC 格式不對");
   v->nal_len = (c[4] & 3) + 1;
   size_t p = 5;
   for (int pass = 0; pass < 2; pass++) {
      if (p >= len) FAIL(H264VCN_UNSUPPORTED, "avcC 太短");
      int n = pass == 0 ? (c[p] & 31) : c[p];
      p++;
      for (int i = 0; i < n; i++) {
         if (p + 2 > len) FAIL(H264VCN_UNSUPPORTED, "avcC 參數集長度錯");
         size_t l = (size_t)c[p] << 8 | c[p + 1];
         p += 2;
         if (p + l > len || !l) FAIL(H264VCN_UNSUPPORTED, "avcC 參數集超出");
         int r = pass == 0 ? h264_parse_sps(&v->ps, c + p, l) : h264_parse_pps(&v->ps, c + p, l);
         if (r) FAIL(H264VCN_UNSUPPORTED, pass == 0 ? "SPS 解析失敗" : "PPS 解析失敗（FMO 等不支援）");
         p += l;
      }
   }
   const h264_sps *sps = NULL;
   for (int i = 0; i < H264_MAX_SPS; i++)
      if (v->ps.sps[i].valid) { sps = &v->ps.sps[i]; v->sps_id = i; break; }
   if (!sps) FAIL(H264VCN_UNSUPPORTED, "沒有 SPS");
   if (!sps->frame_mbs_only_flag) FAIL(H264VCN_UNSUPPORTED, "交錯式（field／MBAFF）不支援");
   if (sps->chroma_format_idc != 1 || sps->bit_depth_luma_minus8 || sps->bit_depth_chroma_minus8)
      FAIL(H264VCN_UNSUPPORTED, "只支援 8-bit 4:2:0");
   if (sps->profile_idc != 66 && sps->profile_idc != 77 && sps->profile_idc != 100)
      FAIL(H264VCN_UNSUPPORTED, "只支援 Baseline／Main／High");
   vcn_h264_layout_init(&v->l, sps);
   v->cw = v->l.width - 2 * (sps->crop_left + sps->crop_right);
   v->ch = v->l.height - 2 * (sps->crop_top + sps->crop_bottom);
   v->x0 = 2 * sps->crop_left;
   v->y0 = 2 * sps->crop_top;
   // kext 的解碼區：+0x0D000000 到 256 MiB（48 MiB），扣掉 session／msg 等 0x23000 和 bitstream 4 MiB
   const uint64_t need = 0x23000ull + BS_CAP + ((v->l.dpb_size + 4095ull) & ~4095ull) + ((v->l.hw_ctx_size + 4095ull) & ~4095ull) + v->l.dt_size;
   if (need > 0x3000000ull) FAIL(H264VCN_UNSUPPORTED, "畫面太大或參考畫面太多，超出 kext 的 VRAM 區");

   v->inbuf = malloc(BS_CAP + 65536);
   v->bs = malloc(BS_CAP);
   v->out = malloc(v->l.dt_size);
   if (!v->inbuf || !v->bs || !v->out) FAIL(H264VCN_MEMORY, "記憶體不足");

   io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("PhxBringup"));
   if (!svc) FAIL(H264VCN_NOT_AVAILABLE, "找不到 PhxBringup");
   kern_return_t kr = IOServiceOpen(svc, mach_task_self(), UC_TYPE, &v->conn);
   IOObjectRelease(svc);
   if (kr) FAIL(H264VCN_NOT_AVAILABLE, "打不開 PhxBringup");
   uint64_t hin[2] = {1, 0}, hout[4];
   uint32_t hn = 4;
   if (IOConnectCallScalarMethod(v->conn, SEL_HELLO, hin, 2, hout, &hn)) FAIL(H264VCN_NOT_AVAILABLE, "Hello 失敗");
   if (hout[1] < MIN_KEXT_BUILD) FAIL(H264VCN_NOT_AVAILABLE, "PhxBringup 太舊（要 build 135 以上）");

   v->handle = 0x46770000u | (__atomic_add_fetch(&g_handles, 1, __ATOMIC_RELAXED) & 0xffffu);
   uint32_t w[14];
   uint32_t n = vcn_h264_session_msg(w, 0, v->handle, &v->l);
   uint64_t res[4];
   int r = kcall(v, 1, n * 4, w, 0, NULL, 0, NULL, 0, res);
   if (r == 1) FAIL(H264VCN_NOT_AVAILABLE, "VCN 沒帶起來（開機時 phxboot 要跑 vcnctl up）");
   if (r == 2) FAIL(H264VCN_NOT_AVAILABLE, "VCN 正在被別的 session 使用");
   if (r) FAIL(H264VCN_DEVICE, "建立 session 失敗");
   v->session_open = 1;
   h264_dpb_init(&v->dpb, v->l.max_num_ref);

   // 輸出 pool：NV12 video range、IOSurface
   int32_t cw = (int32_t)v->cw, ch = (int32_t)v->ch;
   CFNumberRef fmt = CFNumberCreate(NULL, kCFNumberSInt32Type, &(int32_t){kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange});
   CFNumberRef wn = CFNumberCreate(NULL, kCFNumberSInt32Type, &cw), hn2 = CFNumberCreate(NULL, kCFNumberSInt32Type, &ch);
   CFDictionaryRef ios = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
   const void *k[] = {kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey, kCVPixelBufferHeightKey, kCVPixelBufferIOSurfacePropertiesKey};
   const void *vals[] = {fmt, wn, hn2, ios};
   CFDictionaryRef attrs = CFDictionaryCreate(NULL, k, vals, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
   CVReturn cr = CVPixelBufferPoolCreate(NULL, NULL, attrs, &v->pool);
   CFRelease(attrs); CFRelease(ios); CFRelease(fmt); CFRelease(wn); CFRelease(hn2);
   if (cr || !v->pool) FAIL(H264VCN_MEMORY, "CVPixelBufferPool 建立失敗");
   *why = H264VCN_OK;
   return v;
#undef FAIL
}

CFDictionaryRef h264vcn_copy_pixel_buffer_attributes(const H264Vcn *v)
{
   int32_t cw = (int32_t)v->cw, ch = (int32_t)v->ch, f = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
   CFNumberRef fmt = CFNumberCreate(NULL, kCFNumberSInt32Type, &f);
   CFNumberRef wn = CFNumberCreate(NULL, kCFNumberSInt32Type, &cw), hn = CFNumberCreate(NULL, kCFNumberSInt32Type, &ch);
   CFDictionaryRef ios = CFDictionaryCreate(NULL, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
   const void *k[] = {kCVPixelBufferPixelFormatTypeKey, kCVPixelBufferWidthKey, kCVPixelBufferHeightKey, kCVPixelBufferIOSurfacePropertiesKey};
   const void *vals[] = {fmt, wn, hn, ios};
   CFDictionaryRef d = CFDictionaryCreate(NULL, k, vals, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
   CFRelease(fmt); CFRelease(wn); CFRelease(hn); CFRelease(ios);
   return d;
}

void h264vcn_destroy(H264Vcn *v)
{
   if (!v) return;
   if (v->session_open && v->conn) {
      uint32_t w[14];
      uint32_t n = vcn_h264_session_msg(w, 1, v->handle, &v->l);
      uint64_t res[4];
      kcall(v, 3, n * 4, w, 0, NULL, 0, NULL, 0, res);
   }
   if (v->conn) IOServiceClose(v->conn);
   if (v->pool) CVPixelBufferPoolRelease(v->pool);
   free(v->inbuf);
   free(v->bs);
   free(v->out);
   free(v);
}

int h264vcn_decode(H264Vcn *v, const uint8_t *s, size_t len, CVPixelBufferRef *out, H264VcnOrder *order)
{
   *out = NULL;
   uint32_t bsd = 0;
   h264_slice first;
   int nslices = 0;
   for (size_t p = 0; p + (size_t)v->nal_len <= len;) {
      size_t l = 0;
      for (int i = 0; i < v->nal_len; i++) l = l << 8 | s[p + i];
      p += (size_t)v->nal_len;
      if (!l || p + l > len) { seterr(v, "NAL 長度超出 sample"); return H264VCN_BAD_DATA; }
      const uint8_t *nal = s + p;
      p += l;
      int t = nal[0] & 31;
      if (t == 7) {   // in-band SPS：尺寸不能變（變了 VideoToolbox 會用新的格式描述重開 session）
         if (h264_parse_sps(&v->ps, nal, l)) { seterr(v, "in-band SPS 解析失敗"); return H264VCN_BAD_DATA; }
         continue;
      }
      if (t == 8) {
         if (h264_parse_pps(&v->ps, nal, l)) { seterr(v, "in-band PPS 解析失敗"); return H264VCN_BAD_DATA; }
         continue;
      }
      if (t != 1 && t != 5) continue;
      h264_slice sl;
      if (h264_parse_slice(&v->ps, nal, l, &sl)) { seterr(v, "slice header 解析失敗"); return H264VCN_BAD_DATA; }
      if (!nslices) first = sl;
      if (bsd + 3 + l > BS_CAP) { seterr(v, "bitstream 超過 4 MiB"); return H264VCN_BAD_DATA; }
      v->bs[bsd++] = 0; v->bs[bsd++] = 0; v->bs[bsd++] = 1;
      memcpy(v->bs + bsd, nal, l);
      bsd += (uint32_t)l;
      nslices++;
   }
   if (!nslices) { seterr(v, "sample 裡沒有 slice"); return H264VCN_BAD_DATA; }
   const h264_pps *pps = &v->ps.pps[first.pps_id];
   const h264_sps *sps = &v->ps.sps[pps->sps_id];
   if ((sps->pic_width_in_mbs_minus1 + 1) * 16 != v->l.width) { seterr(v, "串流中途改了尺寸"); return H264VCN_BAD_DATA; }
   vcn_h264_pic pic;
   h264_out_info oi;
   if (h264_dpb_begin(&v->dpb, sps, &first, &pic, &oi)) { seterr(v, "DPB 錯誤"); return H264VCN_BAD_DATA; }
   static __thread uint8_t msg[4096];
   rvcn_dec_avc_its_t its;
   uint32_t mb = vcn_h264_decode_msg(msg, &its, v->handle, &v->l, sps, pps, &first, &pic, bsd);
   memset(v->bs + bsd, 0, 4);
   uint64_t res[4];
   int r = kcall(v, 2, mb, msg, sizeof its, &its, bsd, v->out, v->l.dt_size, res);
   if (r) {
      seterr(v, r == 3 ? "VCN 逾時" : r < 0 ? "kext 呼叫失敗" : "kext 回報錯誤");
      return H264VCN_DEVICE;
   }
   v->vcn_us = (uint32_t)res[2];
   h264_dpb_end(&v->dpb, sps, &first, &pic);

   CVPixelBufferRef pb = NULL;
   if (CVPixelBufferPoolCreatePixelBuffer(NULL, v->pool, &pb) || !pb) { seterr(v, "沒有 pixel buffer"); return H264VCN_MEMORY; }
   CVPixelBufferLockBaseAddress(pb, 0);
   uint8_t *y = CVPixelBufferGetBaseAddressOfPlane(pb, 0), *uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1);
   size_t ys = CVPixelBufferGetBytesPerRowOfPlane(pb, 0), uvs = CVPixelBufferGetBytesPerRowOfPlane(pb, 1);
   const uint8_t *sy = v->out + v->y0 * v->l.dt_pitch + v->x0;
   const uint8_t *suv = v->out + v->l.dt_pitch * v->l.dt_height + (v->y0 / 2) * v->l.dt_pitch + v->x0;
   for (uint32_t i = 0; i < v->ch; i++) memcpy(y + i * ys, sy + i * v->l.dt_pitch, v->cw);
   for (uint32_t i = 0; i < v->ch / 2; i++) memcpy(uv + i * uvs, suv + i * v->l.dt_pitch, v->cw);
   CVPixelBufferUnlockBaseAddress(pb, 0);
   *out = pb;
   if (order) {
      order->group = oi.group;
      order->poc = oi.poc;
      order->reorder = sps->max_num_ref_frames ? sps->max_num_ref_frames : 1;
   }
   return H264VCN_OK;
}
