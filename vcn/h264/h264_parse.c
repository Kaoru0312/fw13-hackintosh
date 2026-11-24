// SPDX-License-Identifier: Apache-2.0
// H.264 Annex B 解析（ITU-T H.264 (08/2021) 7.3.2.1.1、7.3.2.2、7.3.3、7.4.2.1.1 表 7-2、8.5.6 表 8-12/8-13）。
#include "h264_parse.h"

#include <string.h>

// ---- bit reader（先把 emulation prevention byte 0x03 拿掉）----
typedef struct {
   uint8_t buf[65536];
   size_t bytes, bit;
   int err;
} br;

static void br_init(br *b, const uint8_t *nal, size_t len)
{
   size_t n = 0, zeros = 0;
   for (size_t i = 0; i < len && n < sizeof b->buf; i++) {
      if (zeros >= 2 && nal[i] == 3) {   // 0x000003 → 0x0000
         zeros = 0;
         continue;
      }
      b->buf[n++] = nal[i];
      zeros = nal[i] == 0 ? zeros + 1 : 0;
   }
   b->bytes = n;
   b->bit = 0;
   b->err = 0;
}

static uint32_t u1(br *b)
{
   if (b->bit >= b->bytes * 8) {
      b->err = 1;
      return 0;
   }
   uint32_t v = (b->buf[b->bit >> 3] >> (7 - (b->bit & 7))) & 1;
   b->bit++;
   return v;
}

static uint32_t un(br *b, int n)
{
   uint32_t v = 0;
   while (n--)
      v = (v << 1) | u1(b);
   return v;
}

static uint32_t ue(br *b)
{
   int lz = 0;
   while (!u1(b)) {
      if (b->err || ++lz > 31) {
         b->err = 1;
         return 0;
      }
   }
   return lz ? ((1u << lz) - 1) + un(b, lz) : 0;
}

static int32_t se(br *b)
{
   uint32_t k = ue(b);
   return (k & 1) ? (int32_t)((k + 1) / 2) : -(int32_t)(k / 2);
}

// 7.2 more_rbsp_data()：目前位置之後，除了最後的 rbsp_stop_one_bit 和補 0，還有沒有資料
static int more_rbsp_data(const br *b)
{
   size_t last = b->bytes;
   while (last > 0 && b->buf[last - 1] == 0)
      last--;
   if (!last)
      return 0;
   uint8_t v = b->buf[last - 1];
   int tz = 0;
   while (!(v & 1)) {
      v >>= 1;
      tz++;
   }
   size_t stop_bit = (last - 1) * 8 + (7 - tz);   // rbsp_stop_one_bit 的位置
   return b->bit < stop_bit;
}

// ---- scaling list ----
static const uint8_t zigzag4x4[16] = {0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15};
static const uint8_t zigzag8x8[64] = {
   0,  1,  8,  16, 9,  2,  3,  10, 17, 24, 32, 25, 18, 11, 4,  5,  12, 19, 26, 33, 40, 48,
   41, 34, 27, 20, 13, 6,  7,  14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23,
   30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63};
// 表 7-3、7-4（zigzag 順序）
static const uint8_t default_4x4_intra[16] = {6, 13, 13, 20, 20, 20, 28, 28, 28, 28, 32, 32, 32, 37, 37, 42};
static const uint8_t default_4x4_inter[16] = {10, 14, 14, 20, 20, 20, 24, 24, 24, 24, 27, 27, 27, 30, 30, 34};
static const uint8_t default_8x8_intra[64] = {
   6,  10, 10, 13, 11, 13, 16, 16, 16, 16, 18, 18, 18, 18, 18, 23, 23, 23, 23, 23, 23, 25,
   25, 25, 25, 25, 25, 25, 27, 27, 27, 27, 27, 27, 27, 27, 29, 29, 29, 29, 29, 29, 29, 31,
   31, 31, 31, 31, 31, 33, 33, 33, 33, 33, 36, 36, 36, 36, 38, 38, 38, 40, 40, 42};
static const uint8_t default_8x8_inter[64] = {
   9,  13, 13, 15, 13, 15, 17, 17, 17, 17, 19, 19, 19, 19, 19, 21, 21, 21, 21, 21, 21, 22,
   22, 22, 22, 22, 22, 22, 24, 24, 24, 24, 24, 24, 24, 24, 25, 25, 25, 25, 25, 25, 25, 27,
   27, 27, 27, 27, 27, 28, 28, 28, 28, 28, 30, 30, 30, 30, 32, 32, 32, 33, 33, 35};

static void set_list(uint8_t *dst, const uint8_t *zz_values, int n)
{
   const uint8_t *scan = n == 16 ? zigzag4x4 : zigzag8x8;
   for (int i = 0; i < n; i++)
      dst[scan[i]] = zz_values[i];
}

// 7.3.2.1.1.1 scaling_list()。回傳 1 = 用 default（useDefaultScalingMatrixFlag）
static int read_list(br *b, uint8_t *dst, int n)
{
   uint8_t zz[64];
   int last = 8, next = 8;
   for (int j = 0; j < n; j++) {
      if (next) {
         next = (last + se(b) + 256) % 256;
         if (j == 0 && next == 0)
            return 1;
      }
      zz[j] = (uint8_t)(next ? next : last);
      last = zz[j];
   }
   set_list(dst, zz, n);
   return 0;
}

// fall-back：i 是 list 編號（0..5 是 4x4，6..11 是 8x8）。rule_a：沒有前一層時用 default（SPS）；rule_b：用 SPS 的值（PPS）
static void read_lists(br *b, int count, uint8_t l4[6][16], uint8_t l8[6][64], const uint8_t (*fb4)[16],
                       const uint8_t (*fb8)[64])
{
   for (int i = 0; i < count; i++) {
      int present = u1(b);
      if (i < 6) {
         const uint8_t *def = i < 3 ? default_4x4_intra : default_4x4_inter;
         if (present) {
            if (read_list(b, l4[i], 16))
               set_list(l4[i], def, 16);
         } else if (i == 0 || i == 3) {
            if (fb4)
               memcpy(l4[i], fb4[i], 16);
            else
               set_list(l4[i], def, 16);
         } else {
            memcpy(l4[i], l4[i - 1], 16);
         }
      } else {
         int k = i - 6;
         const uint8_t *def = (k % 2 == 0) ? default_8x8_intra : default_8x8_inter;
         if (present) {
            if (read_list(b, l8[k], 64))
               set_list(l8[k], def, 64);
         } else if (k < 2) {
            if (fb8)
               memcpy(l8[k], fb8[k], 64);
            else
               set_list(l8[k], def, 64);
         } else {
            memcpy(l8[k], l8[k - 2], 64);
         }
      }
   }
}

static void flat_lists(uint8_t l4[6][16], uint8_t l8[6][64])
{
   memset(l4, 16, 6 * 16);
   memset(l8, 16, 6 * 64);
}

// ---- NAL ----
const uint8_t *h264_next_nal(const uint8_t *buf, size_t size, size_t *pos, size_t *len)
{
   size_t i = *pos;
   while (i + 3 <= size && !(buf[i] == 0 && buf[i + 1] == 0 && buf[i + 2] == 1))
      i++;
   if (i + 3 > size)
      return NULL;
   size_t start = i + 3, j = start;
   while (j + 3 <= size && !(buf[j] == 0 && buf[j + 1] == 0 && (buf[j + 2] == 1 || (buf[j + 2] == 0 && j + 3 < size && buf[j + 3] == 1))))
      j++;
   if (j + 3 > size)
      j = size;
   size_t end = j;
   while (end > start && buf[end - 1] == 0)   // 去掉 trailing_zero_8bits
      end--;
   *len = end - start;
   *pos = j;
   return buf + start;
}

static int high_profile(uint8_t p)
{
   return p == 100 || p == 110 || p == 122 || p == 244 || p == 44 || p == 83 || p == 86 || p == 118 || p == 128 ||
          p == 138 || p == 139 || p == 134 || p == 135;
}

int h264_parse_sps(h264_params *p, const uint8_t *nal, size_t len)
{
   static br b;
   br_init(&b, nal, len);
   un(&b, 8);   // NAL header
   h264_sps s;
   memset(&s, 0, sizeof s);
   s.profile_idc = (uint8_t)un(&b, 8);
   s.constraint_flags = (uint8_t)un(&b, 8);
   s.level_idc = (uint8_t)un(&b, 8);
   uint32_t id = ue(&b);
   if (id >= H264_MAX_SPS)
      return -1;
   s.sps_id = (uint8_t)id;
   s.chroma_format_idc = 1;
   flat_lists(s.scaling_list_4x4, s.scaling_list_8x8);
   if (high_profile(s.profile_idc)) {
      s.chroma_format_idc = (uint8_t)ue(&b);
      if (s.chroma_format_idc == 3)
         s.separate_colour_plane_flag = (uint8_t)u1(&b);
      s.bit_depth_luma_minus8 = (uint8_t)ue(&b);
      s.bit_depth_chroma_minus8 = (uint8_t)ue(&b);
      s.qpprime_y_zero_transform_bypass_flag = (uint8_t)u1(&b);
      s.seq_scaling_matrix_present_flag = (uint8_t)u1(&b);
      if (s.seq_scaling_matrix_present_flag)
         read_lists(&b, s.chroma_format_idc != 3 ? 8 : 12, s.scaling_list_4x4, s.scaling_list_8x8, NULL, NULL);
   }
   s.log2_max_frame_num_minus4 = (uint8_t)ue(&b);
   s.pic_order_cnt_type = (uint8_t)ue(&b);
   if (s.pic_order_cnt_type == 0) {
      s.log2_max_pic_order_cnt_lsb_minus4 = (uint8_t)ue(&b);
   } else if (s.pic_order_cnt_type == 1) {
      s.delta_pic_order_always_zero_flag = (uint8_t)u1(&b);
      s.offset_for_non_ref_pic = se(&b);
      s.offset_for_top_to_bottom_field = se(&b);
      uint32_t n = ue(&b);
      if (n > 255)
         return -1;
      s.num_ref_frames_in_pic_order_cnt_cycle = (uint8_t)n;
      for (uint32_t i = 0; i < n; i++)
         s.offset_for_ref_frame[i] = se(&b);
   }
   s.max_num_ref_frames = (uint8_t)ue(&b);
   s.gaps_in_frame_num_value_allowed_flag = (uint8_t)u1(&b);
   s.pic_width_in_mbs_minus1 = ue(&b);
   s.pic_height_in_map_units_minus1 = ue(&b);
   s.frame_mbs_only_flag = (uint8_t)u1(&b);
   if (!s.frame_mbs_only_flag)
      s.mb_adaptive_frame_field_flag = (uint8_t)u1(&b);
   s.direct_8x8_inference_flag = (uint8_t)u1(&b);
   s.frame_cropping_flag = (uint8_t)u1(&b);
   if (s.frame_cropping_flag) {
      s.crop_left = ue(&b);
      s.crop_right = ue(&b);
      s.crop_top = ue(&b);
      s.crop_bottom = ue(&b);
   }
   // VUI 不需要
   if (b.err || s.log2_max_frame_num_minus4 > 12 || s.log2_max_pic_order_cnt_lsb_minus4 > 12 ||
       s.pic_order_cnt_type > 2)
      return -1;
   s.valid = 1;
   p->sps[s.sps_id] = s;
   return 0;
}

int h264_parse_pps(h264_params *p, const uint8_t *nal, size_t len)
{
   static br b;
   br_init(&b, nal, len);
   un(&b, 8);
   h264_pps q;
   memset(&q, 0, sizeof q);
   uint32_t id = ue(&b), sid = ue(&b);
   if (id >= H264_MAX_PPS || sid >= H264_MAX_SPS || !p->sps[sid].valid)
      return -1;
   const h264_sps *s = &p->sps[sid];
   q.pps_id = (uint8_t)id;
   q.sps_id = (uint8_t)sid;
   q.entropy_coding_mode_flag = (uint8_t)u1(&b);
   q.bottom_field_pic_order_in_frame_present_flag = (uint8_t)u1(&b);
   q.num_slice_groups_minus1 = (uint8_t)ue(&b);
   if (q.num_slice_groups_minus1)   // FMO（只有 Baseline／Extended 才有），不支援
      return -2;
   q.num_ref_idx_l0_default_active_minus1 = (uint8_t)ue(&b);
   q.num_ref_idx_l1_default_active_minus1 = (uint8_t)ue(&b);
   q.weighted_pred_flag = (uint8_t)u1(&b);
   q.weighted_bipred_idc = (uint8_t)un(&b, 2);
   q.pic_init_qp_minus26 = (int8_t)se(&b);
   q.pic_init_qs_minus26 = (int8_t)se(&b);
   q.chroma_qp_index_offset = (int8_t)se(&b);
   q.deblocking_filter_control_present_flag = (uint8_t)u1(&b);
   q.constrained_intra_pred_flag = (uint8_t)u1(&b);
   q.redundant_pic_cnt_present_flag = (uint8_t)u1(&b);
   memcpy(q.scaling_list_4x4, s->scaling_list_4x4, sizeof q.scaling_list_4x4);
   memcpy(q.scaling_list_8x8, s->scaling_list_8x8, sizeof q.scaling_list_8x8);
   q.second_chroma_qp_index_offset = q.chroma_qp_index_offset;
   if (more_rbsp_data(&b)) {
      q.transform_8x8_mode_flag = (uint8_t)u1(&b);
      if (u1(&b)) {   // pic_scaling_matrix_present_flag：fall-back rule B（沒給的用 SPS 的；SPS 沒給 matrix 時 rule A）
         int n = 6 + ((s->chroma_format_idc != 3) ? 2 : 6) * q.transform_8x8_mode_flag;
         if (s->seq_scaling_matrix_present_flag)
            read_lists(&b, n, q.scaling_list_4x4, q.scaling_list_8x8, s->scaling_list_4x4, s->scaling_list_8x8);
         else
            read_lists(&b, n, q.scaling_list_4x4, q.scaling_list_8x8, NULL, NULL);
      }
      q.second_chroma_qp_index_offset = (int8_t)se(&b);
   }
   if (b.err)
      return -1;
   q.valid = 1;
   p->pps[q.pps_id] = q;
   return 0;
}

int h264_parse_slice(const h264_params *p, const uint8_t *nal, size_t len, h264_slice *sl)
{
   static br b;
   br_init(&b, nal, len);
   memset(sl, 0, sizeof *sl);
   uint32_t h = un(&b, 8);
   sl->nal_ref_idc = (h >> 5) & 3;
   sl->nal_unit_type = h & 31;
   sl->first_mb_in_slice = ue(&b);
   uint32_t st = ue(&b);
   if (st > 9)
      return -1;
   sl->slice_type = (uint8_t)(st % 5);
   uint32_t pid = ue(&b);
   if (pid >= H264_MAX_PPS || !p->pps[pid].valid)
      return -1;
   sl->pps_id = (uint8_t)pid;
   const h264_pps *q = &p->pps[pid];
   const h264_sps *s = &p->sps[q->sps_id];
   if (!s->valid)
      return -1;
   if (s->separate_colour_plane_flag)
      un(&b, 2);
   sl->frame_num = un(&b, s->log2_max_frame_num_minus4 + 4);
   if (!s->frame_mbs_only_flag) {
      sl->field_pic_flag = (uint8_t)u1(&b);
      if (sl->field_pic_flag)
         sl->bottom_field_flag = (uint8_t)u1(&b);
   }
   if (sl->nal_unit_type == 5)
      sl->idr_pic_id = ue(&b);
   if (s->pic_order_cnt_type == 0) {
      sl->pic_order_cnt_lsb = un(&b, s->log2_max_pic_order_cnt_lsb_minus4 + 4);
      if (q->bottom_field_pic_order_in_frame_present_flag && !sl->field_pic_flag)
         sl->delta_pic_order_cnt_bottom = se(&b);
   }
   if (s->pic_order_cnt_type == 1 && !s->delta_pic_order_always_zero_flag) {
      sl->delta_pic_order_cnt[0] = se(&b);
      if (q->bottom_field_pic_order_in_frame_present_flag && !sl->field_pic_flag)
         sl->delta_pic_order_cnt[1] = se(&b);
   }
   if (q->redundant_pic_cnt_present_flag)
      ue(&b);
   const int is_b = sl->slice_type == 1, is_p = sl->slice_type == 0 || sl->slice_type == 3,
             is_i = sl->slice_type == 2 || sl->slice_type == 4;
   if (is_b)
      u1(&b);   // direct_spatial_mv_pred_flag
   sl->num_ref_idx_l0_active_minus1 = q->num_ref_idx_l0_default_active_minus1;
   sl->num_ref_idx_l1_active_minus1 = q->num_ref_idx_l1_default_active_minus1;
   if (is_p || is_b) {
      if (u1(&b)) {   // num_ref_idx_active_override_flag
         sl->num_ref_idx_l0_active_minus1 = (uint8_t)ue(&b);
         if (is_b)
            sl->num_ref_idx_l1_active_minus1 = (uint8_t)ue(&b);
      }
   }
   // ref_pic_list_modification()（nal_unit_type 20/21 的 MVC 版本不支援）
   for (int list = 0; list < (is_b ? 2 : 1); list++) {
      if (is_i)
         break;
      if (u1(&b)) {
         uint32_t idc;
         int guard = 0;
         do {
            idc = ue(&b);
            if (idc == 0 || idc == 1 || idc == 2)
               ue(&b);
         } while (idc != 3 && !b.err && ++guard < 64);
      }
   }
   // pred_weight_table()
   if ((q->weighted_pred_flag && is_p) || (q->weighted_bipred_idc == 1 && is_b)) {
      ue(&b);   // luma_log2_weight_denom
      const int chroma = s->chroma_format_idc != 0 && !s->separate_colour_plane_flag;
      if (chroma)
         ue(&b);
      for (int list = 0; list < (is_b ? 2 : 1); list++) {
         int n = (list ? sl->num_ref_idx_l1_active_minus1 : sl->num_ref_idx_l0_active_minus1) + 1;
         for (int i = 0; i < n; i++) {
            if (u1(&b)) {
               se(&b);
               se(&b);
            }
            if (chroma && u1(&b))
               for (int j = 0; j < 4; j++)
                  se(&b);
         }
      }
   }
   // dec_ref_pic_marking()
   if (sl->nal_ref_idc) {
      if (sl->nal_unit_type == 5) {
         sl->no_output_of_prior_pics_flag = (uint8_t)u1(&b);
         sl->long_term_reference_flag = (uint8_t)u1(&b);
      } else {
         sl->adaptive_ref_pic_marking_mode_flag = (uint8_t)u1(&b);
         if (sl->adaptive_ref_pic_marking_mode_flag) {
            uint32_t op;
            do {
               op = ue(&b);
               if (op && sl->num_mmco < 32) {
                  h264_mmco *m = &sl->mmco[sl->num_mmco++];
                  m->idc = (uint8_t)op;
                  if (op == 1 || op == 3)
                     m->a = ue(&b);   // difference_of_pic_nums_minus1
                  if (op == 2)
                     m->a = ue(&b);   // long_term_pic_num
                  if (op == 3 || op == 6)
                     m->b = ue(&b);   // long_term_frame_idx
                  if (op == 4)
                     m->a = ue(&b);   // max_long_term_frame_idx_plus1
               }
            } while (op && !b.err && sl->num_mmco < 32);
         }
      }
   }
   return b.err ? -1 : 0;
}
