// SPDX-License-Identifier: Apache-2.0
// 主機端測試（Linux／macOS 都能跑，不碰 GPU）：
//   1. 用 libdrm 向量的 SPS／PPS 參數組 avc message，跟 vcn_dec_vector.h 的 kDecodeH264Parameters 逐 byte 比對（驗證結構版面）。
//   2. 解析 testdata/*.h264，印出 SPS／PPS／slice 與 VCN 版面。
// cc -std=c11 -O2 -Wall -Wextra -I. vcn/h264/test_h264.c vcn/h264/h264_parse.c vcn/h264/vcn_h264_msg.c -o /tmp/test_h264
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../vcn_dec_vector.h"
#include "h264_parse.h"
#include "vcn_h264_msg.h"
#include "h264_dpb.h"
#include "h264_stream.h"

static int fails;
#define CHECK(c, ...) do { if (!(c)) { printf("  ✗ " __VA_ARGS__); printf("\n"); fails++; } } while (0)

static void test_libdrm_layout(void)
{
   printf("== 1. avc 結構 vs libdrm 向量\n");
   h264_sps s;
   h264_pps p;
   h264_slice sl;
   memset(&sl, 0, sizeof sl);
   vcn_h264_libdrm_params(&s, &p);
   vcn_h264_layout l;
   vcn_h264_layout_init(&l, &s);
   vcn_h264_pic pic;
   memset(&pic, 0, sizeof pic);
   static uint8_t msg[4096];
   rvcn_dec_avc_its_t its;
   uint32_t n = vcn_h264_decode_msg(msg, &its, 0x40440003, &l, &s, &p, &sl, &pic, 1408);
   const uint8_t *avc = msg + 0x38 + sizeof(rvcn_dec_message_decode_t);   // 向量的 avc 在 0xec（舊版 decode 180 bytes）
   // 向量的 avc 區塊：kDecodeH264Parameters 的前 1116 bytes（向量的 index size 0x45c，沒有 Mesa 後加的兩個欄位）
   int diff = 0;
   for (int i = 0; i < 1116; i++)
      if (avc[i] != kDecodeH264Parameters[i]) {
         if (diff < 8)
            printf("  avc +%d：我們 0x%02x、向量 0x%02x\n", i, avc[i], kDecodeH264Parameters[i]);
         diff++;
      }
   CHECK(diff == 0, "avc 結構有 %d bytes 不同", diff);
   if (!diff)
      printf("  ✅ avc 結構前 1116 bytes 跟向量逐 byte 相同\n");
   CHECK(memcmp(&its, kDecodeH264ScalingTable, 224) == 0, "IT scaling buffer 跟向量不同");
   // header／decode：版面一致的部分
   const uint32_t *w = (const uint32_t *)msg;
   const uint32_t *v = (const uint32_t *)kDecodeH264Message;
   CHECK(w[0] == v[0] && w[2] == v[2] && w[3] == v[3] && w[4] == v[4] && w[5] == v[5], "header 不同");
   CHECK(w[6] == v[6] && w[7] == v[7] && w[10] == v[10], "index 的 message id／decode offset 不同");
   printf("  index：decode size 我們 %u、向量 %u；avc offset 我們 0x%x、向量 0x%x；avc size 我們 %u、向量 %u\n", w[8], v[8], w[11], v[11], w[12], v[12]);
   printf("  header total_size：我們 %u、向量 %u（Mesa 的算法 vs libdrm；不影響）\n", w[1], v[1]);
   printf("  decode 欄位差異（Mesa TIER0 vs libdrm 向量）：\n");
   const char *names[] = {"stream_type", "decode_flags", "width", "height", "bsd_size", "dpb_size", "dt_size", "sct_size",
                          "sc_coeff_size", "hw_ctxt_size", "sw_ctxt_size", "pic_param_size", "mb_cntl_size", "r0", "r1", "r2",
                          "r3", "decode_buffer_flags", "db_pitch", "db_aligned_height", "db_tiling_mode", "db_swizzle_mode",
                          "db_array_mode", "db_field_mode", "db_surf_tile_config", "dt_pitch", "dt_uv_pitch",
                          "dt_tiling_mode", "dt_swizzle_mode", "dt_array_mode", "dt_field_mode", "dt_out_format",
                          "dt_surf_tile_config", "dt_uv_surf_tile_config", "dt_luma_top", "dt_luma_bottom", "dt_chroma_top",
                          "dt_chroma_bottom", "dt_chromaV_top", "dt_chromaV_bottom", "mif_wrc_en", "db_pitch_uv"};
   for (int i = 0; i < 42; i++)
      if (w[14 + i] != v[14 + i])
         printf("    %-20s 我們 %u、向量 %u\n", names[i], w[14 + i], v[14 + i]);
   (void)n;
}

static int test_file(const char *path)
{
   FILE *f = fopen(path, "rb");
   if (!f) {
      printf("  ✗ 打不開 %s\n", path);
      return ++fails;
   }
   static uint8_t buf[1 << 20];
   size_t size = fread(buf, 1, sizeof buf, f);
   fclose(f);
   printf("== %s（%zu bytes）\n", path, size);
   static h264_params ps;
   memset(&ps, 0, sizeof ps);
   size_t pos = 0, len;
   const uint8_t *nal;
   int slices = 0;
   while ((nal = h264_next_nal(buf, size, &pos, &len))) {
      int type = nal[0] & 31;
      if (type == 7) {
         int r = h264_parse_sps(&ps, nal, len);
         const h264_sps *s = &ps.sps[0];
         printf("  SPS r=%d profile %u level %u chroma %u %ux%u MB frame_mbs_only %u poc_type %u max_ref %u crop %u/%u/%u/%u scaling %u\n",
                r, s->profile_idc, s->level_idc, s->chroma_format_idc, s->pic_width_in_mbs_minus1 + 1,
                s->pic_height_in_map_units_minus1 + 1, s->frame_mbs_only_flag, s->pic_order_cnt_type, s->max_num_ref_frames,
                s->crop_left, s->crop_right, s->crop_top, s->crop_bottom, s->seq_scaling_matrix_present_flag);
         CHECK(r == 0, "SPS 解析失敗");
      } else if (type == 8) {
         int r = h264_parse_pps(&ps, nal, len);
         const h264_pps *q = &ps.pps[0];
         printf("  PPS r=%d cabac %u 8x8 %u qp %d chroma_qp %d/%d deblock %u wp %u/%u\n", r, q->entropy_coding_mode_flag,
                q->transform_8x8_mode_flag, q->pic_init_qp_minus26 + 26, q->chroma_qp_index_offset,
                q->second_chroma_qp_index_offset, q->deblocking_filter_control_present_flag, q->weighted_pred_flag,
                q->weighted_bipred_idc);
         CHECK(r == 0, "PPS 解析失敗");
      } else if (type == 1 || type == 5) {
         h264_slice sl;
         int r = h264_parse_slice(&ps, nal, len, &sl);
         printf("  slice r=%d nal %u ref_idc %u type %u first_mb %u frame_num %u poc_lsb %u idr_id %u\n", r, sl.nal_unit_type,
                sl.nal_ref_idc, sl.slice_type, sl.first_mb_in_slice, sl.frame_num, sl.pic_order_cnt_lsb, sl.idr_pic_id);
         CHECK(r == 0, "slice header 解析失敗");
         if (!slices++ && r == 0) {
            vcn_h264_layout l;
            vcn_h264_layout_init(&l, &ps.sps[ps.pps[sl.pps_id].sps_id]);
            printf("  VCN 版面：%ux%u max_ref %u dpb %u ctx %u db_pitch %u/%u h %u dt_pitch %u dt_size %u\n", l.width,
                   l.height, l.max_num_ref, l.dpb_size, l.hw_ctx_size, l.db_pitch, l.db_pitch_uv, l.db_aligned_height,
                   l.dt_pitch, l.dt_size);
         }
      } else {
         printf("  NAL type %d（%zu bytes，略過）\n", type, len);
      }
   }
   CHECK(slices > 0, "沒有 slice");
   return 0;
}


// 3. 用 parser + DPB 模擬整支串流：依 (group, POC) 排序的解碼順序要等於 ffprobe 的 coded_picture_number（.order 檔）
typedef struct { uint32_t group; int32_t poc; int idx; } outrec;
static int cmp_out(const void *a, const void *b)
{
   const outrec *x = a, *y = b;
   if (x->group != y->group) return x->group < y->group ? -1 : 1;
   return x->poc < y->poc ? -1 : x->poc > y->poc;
}

static void test_sim(const char *path)
{
   char order_path[512];
   snprintf(order_path, sizeof order_path, "%.*s.order", (int)(strlen(path) - 5), path);
   FILE *fo = fopen(order_path, "r");
   if (!fo)
      return;   // 沒有答案檔的不測
   int expect[1024], ne = 0;
   while (ne < 1024 && fscanf(fo, "%d", &expect[ne]) == 1) ne++;
   fclose(fo);
   FILE *f = fopen(path, "rb");
   static uint8_t buf[4 << 20], bs[2 << 20];
   size_t size = fread(buf, 1, sizeof buf, f);
   fclose(f);
   static h264_stream st;
   h264_stream_init(&st, buf, size);
   h264_dpb dpb;
   int inited = 0, n = 0, maxrefs = 0;
   uint32_t maxslot = 0;
   static outrec out[1024];
   h264_picture p;
   int r;
   while ((r = h264_stream_next(&st, &p, bs, sizeof bs)) == 1 && n < 1024) {
      const h264_pps *pps = &st.ps.pps[p.first.pps_id];
      const h264_sps *sps = &st.ps.sps[pps->sps_id];
      if (!inited) {
         vcn_h264_layout l;
         vcn_h264_layout_init(&l, sps);
         h264_dpb_init(&dpb, l.max_num_ref);
         inited = 1;
      }
      vcn_h264_pic pic;
      h264_out_info oi;
      int b = h264_dpb_begin(&dpb, sps, &p.first, &pic, &oi);
      CHECK(b == 0, "%s 第 %d 張 dpb_begin 失敗 %d", path, n, b);
      if (b) break;
      if ((int)pic.num_refs > maxrefs) maxrefs = (int)pic.num_refs;
      if (pic.decoded_pic_idx > maxslot) maxslot = pic.decoded_pic_idx;
      out[n].group = oi.group; out[n].poc = oi.poc; out[n].idx = n;
      h264_dpb_end(&dpb, sps, &p.first, &pic);
      n++;
   }
   CHECK(r >= 0, "%s 串流解析錯誤 %d", path, r);
   qsort(out, n, sizeof *out, cmp_out);
   int bad = n != ne;
   for (int i = 0; i < n && i < ne; i++) bad |= out[i].idx != expect[i];
   printf("== 模擬 %s：%d 張（答案 %d 張）、最多 %d 張參考、slot 最大 %u → 顯示順序%s\n", path, n, ne, maxrefs, maxslot,
          bad ? "✗ 跟 ffprobe 不同" : "跟 ffprobe 一致 ✅");
   if (bad) { for (int i = 0; i < n && i < 24; i++) printf("%d ", out[i].idx); printf("\n"); fails++; }
}

int main(int argc, char **argv)
{
   test_libdrm_layout();
   for (int i = 1; i < argc; i++)
      test_file(argv[i]);
   for (int i = 1; i < argc; i++)
      test_sim(argv[i]);
   printf("%s\n", fails ? "✗ 有失敗" : "✅ 全部通過");
   return fails != 0;
}
