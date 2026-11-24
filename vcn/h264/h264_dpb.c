// SPDX-License-Identifier: Apache-2.0
// ITU-T H.264 8.2.1（POC）、8.2.4.1（FrameNumWrap／PicNum）、8.2.5.3（sliding window）、8.2.5.4（MMCO）。frame 模式。
#include "h264_dpb.h"

#include <string.h>

void h264_dpb_init(h264_dpb *d, uint32_t max_slots)
{
   memset(d, 0, sizeof *d);
   d->max_long_term_frame_idx = -1;
   d->max_slots = max_slots > H264_DPB_SLOTS ? H264_DPB_SLOTS : max_slots;
}

static void remove_ref(h264_dpb *d, int i)
{
   d->refs[i] = d->refs[--d->nrefs];
}

static void compute_poc(h264_dpb *d, const h264_sps *s, const h264_slice *sl, int32_t *top, int32_t *bot)
{
   const uint32_t max_frame_num = 1u << (s->log2_max_frame_num_minus4 + 4);
   const int idr = sl->nal_unit_type == 5;
   if (s->pic_order_cnt_type == 0) {
      const int32_t max_lsb = 1 << (s->log2_max_pic_order_cnt_lsb_minus4 + 4);
      int32_t prev_msb, prev_lsb;
      if (idr) {
         prev_msb = prev_lsb = 0;
      } else {   // 前一張參考畫面有 MMCO5 的情況，h264_dpb_end 已經把 prev_poc_* 設成 0 和它調整後的 TopFieldOrderCnt
         prev_msb = d->prev_poc_msb;
         prev_lsb = d->prev_poc_lsb;
      }
      const int32_t lsb = (int32_t)sl->pic_order_cnt_lsb;
      int32_t msb;
      if (lsb < prev_lsb && (prev_lsb - lsb) >= max_lsb / 2)
         msb = prev_msb + max_lsb;
      else if (lsb > prev_lsb && (lsb - prev_lsb) > max_lsb / 2)
         msb = prev_msb - max_lsb;
      else
         msb = prev_msb;
      *top = msb + lsb;
      *bot = *top + sl->delta_pic_order_cnt_bottom;
      if (sl->nal_ref_idc) {   // 8.2.1.1：prevPicOrderCnt* 取自前一張「參考」畫面
         d->prev_poc_msb = msb;
         d->prev_poc_lsb = lsb;
      }
   } else {
      int32_t prev_offset = d->prev_frame_num_offset;   // MMCO5 之後 h264_dpb_end 已設 0
      int32_t offset;
      if (idr)
         offset = 0;
      else if (d->prev_frame_num > sl->frame_num)
         offset = prev_offset + (int32_t)max_frame_num;
      else
         offset = prev_offset;
      if (s->pic_order_cnt_type == 1) {
         int32_t abs_frame_num = 0, expected = 0;
         if (s->num_ref_frames_in_pic_order_cnt_cycle)
            abs_frame_num = offset + (int32_t)sl->frame_num;
         if (!sl->nal_ref_idc && abs_frame_num > 0)
            abs_frame_num--;
         if (abs_frame_num > 0) {
            int32_t delta_cycle = 0;
            for (int i = 0; i < s->num_ref_frames_in_pic_order_cnt_cycle; i++)
               delta_cycle += s->offset_for_ref_frame[i];
            int32_t cnt = (abs_frame_num - 1) / s->num_ref_frames_in_pic_order_cnt_cycle;
            int32_t in_cycle = (abs_frame_num - 1) % s->num_ref_frames_in_pic_order_cnt_cycle;
            expected = cnt * delta_cycle;
            for (int i = 0; i <= in_cycle; i++)
               expected += s->offset_for_ref_frame[i];
         }
         if (!sl->nal_ref_idc)
            expected += s->offset_for_non_ref_pic;
         *top = expected + sl->delta_pic_order_cnt[0];
         *bot = *top + s->offset_for_top_to_bottom_field + sl->delta_pic_order_cnt[1];
      } else {
         int32_t t;
         if (idr)
            t = 0;
         else if (!sl->nal_ref_idc)
            t = 2 * (offset + (int32_t)sl->frame_num) - 1;
         else
            t = 2 * (offset + (int32_t)sl->frame_num);
         *top = *bot = t;
      }
      d->prev_frame_num_offset = offset;
   }
   d->prev_frame_num = sl->frame_num;
}

int h264_dpb_begin(h264_dpb *d, const h264_sps *s, const h264_slice *sl, vcn_h264_pic *pic, h264_out_info *out)
{
   if (!s->frame_mbs_only_flag || sl->field_pic_flag)
      return -1;   // field／MBAFF 不支援
   const uint32_t max_frame_num = 1u << (s->log2_max_frame_num_minus4 + 4);
   if (sl->nal_unit_type == 5) {
      d->nrefs = 0;   // IDR：所有參考畫面在標記階段會被清掉；先清，參考清單才不會帶舊畫面
      d->group++;
   } else if (d->group_bump) {
      d->group++;
   }
   d->group_bump = 0;
   memset(pic, 0, sizeof *pic);
   memset(pic->ref_idx, 0xff, sizeof pic->ref_idx);
   compute_poc(d, s, sl, &pic->top_poc, &pic->bottom_poc);

   // 8.2.4.1：FrameNumWrap
   for (int i = 0; i < d->nrefs; i++) {
      h264_ref *r = &d->refs[i];
      if (!r->long_term)
         r->frame_num_wrap = r->frame_num > sl->frame_num ? (int32_t)r->frame_num - (int32_t)max_frame_num : (int32_t)r->frame_num;
   }
   // 參考清單：目前所有參考畫面（VA-API ReferenceFrames 的語意），順序不重要，韌體用 frame_num_list／POC 對應
   for (int i = 0; i < d->nrefs && i < 16; i++) {
      const h264_ref *r = &d->refs[i];
      pic->ref_idx[i] = (uint8_t)r->slot;
      pic->ref_frame_num[i] = r->long_term ? r->long_term_frame_idx : r->frame_num;
      pic->ref_poc[i][0] = r->top_poc;
      pic->ref_poc[i][1] = r->bottom_poc;
      if (r->long_term)
         pic->long_term_flags |= 1u << i;
      pic->used_for_reference_flags |= 3u << (2 * i);
   }
   pic->num_refs = (uint32_t)d->nrefs;

   // slot：挑一個沒被參考畫面佔用的
   uint32_t slot = 0;
   for (; slot < d->max_slots; slot++) {
      int busy = 0;
      for (int i = 0; i < d->nrefs; i++)
         busy |= d->refs[i].slot == slot;
      if (!busy)
         break;
   }
   if (slot >= d->max_slots)
      return -2;
   pic->decoded_pic_idx = slot;
   out->group = d->group;
   out->poc = pic->top_poc < pic->bottom_poc ? pic->top_poc : pic->bottom_poc;
   return 0;
}

static int find_short_by_picnum(const h264_dpb *d, int32_t picnum)
{
   for (int i = 0; i < d->nrefs; i++)
      if (!d->refs[i].long_term && d->refs[i].frame_num_wrap == picnum)
         return i;
   return -1;
}

static int find_long_by_idx(const h264_dpb *d, uint32_t idx)
{
   for (int i = 0; i < d->nrefs; i++)
      if (d->refs[i].long_term && d->refs[i].long_term_frame_idx == idx)
         return i;
   return -1;
}

void h264_dpb_end(h264_dpb *d, const h264_sps *s, const h264_slice *sl, const vcn_h264_pic *pic)
{
   if (!sl->nal_ref_idc)
      return;   // 非參考畫面：不改變標記
   d->prev_has_mmco5 = 0;
   h264_ref cur;
   memset(&cur, 0, sizeof cur);
   cur.used = 1;
   cur.frame_num = sl->frame_num;
   cur.frame_num_wrap = (int32_t)sl->frame_num;
   cur.top_poc = pic->top_poc;
   cur.bottom_poc = pic->bottom_poc;
   cur.slot = pic->decoded_pic_idx;
   int cur_long = 0;

   if (sl->nal_unit_type == 5) {
      d->nrefs = 0;
      if (sl->long_term_reference_flag) {
         cur_long = 1;
         cur.long_term_frame_idx = 0;
         d->max_long_term_frame_idx = 0;
      } else {
         d->max_long_term_frame_idx = -1;
      }
   } else if (sl->adaptive_ref_pic_marking_mode_flag) {
      const int32_t curr_pic_num = (int32_t)sl->frame_num;
      for (int m = 0; m < sl->num_mmco; m++) {
         const h264_mmco *op = &sl->mmco[m];
         int i;
         switch (op->idc) {
         case 1:   // 短期 → 不參考
            if ((i = find_short_by_picnum(d, curr_pic_num - (int32_t)(op->a + 1))) >= 0)
               remove_ref(d, i);
            break;
         case 2:   // 長期 → 不參考（frame：LongTermPicNum = LongTermFrameIdx）
            if ((i = find_long_by_idx(d, op->a)) >= 0)
               remove_ref(d, i);
            break;
         case 3:   // 短期 → 長期
            if ((i = find_long_by_idx(d, op->b)) >= 0)
               remove_ref(d, i);
            if ((i = find_short_by_picnum(d, curr_pic_num - (int32_t)(op->a + 1))) >= 0) {
               d->refs[i].long_term = 1;
               d->refs[i].long_term_frame_idx = op->b;
            }
            break;
         case 4:   // MaxLongTermFrameIdx
            d->max_long_term_frame_idx = (int)op->a - 1;
            for (i = d->nrefs - 1; i >= 0; i--)
               if (d->refs[i].long_term && (int)d->refs[i].long_term_frame_idx > d->max_long_term_frame_idx)
                  remove_ref(d, i);
            break;
         case 5:   // 全部清掉
            d->nrefs = 0;
            d->max_long_term_frame_idx = -1;
            d->prev_has_mmco5 = 1;
            break;
         case 6:   // 目前這張 → 長期
            if ((i = find_long_by_idx(d, op->b)) >= 0)
               remove_ref(d, i);
            cur_long = 1;
            cur.long_term_frame_idx = op->b;
            break;
         }
      }
   } else {
      // 8.2.5.3 sliding window
      const int max_ref = s->max_num_ref_frames ? s->max_num_ref_frames : 1;
      if (d->nrefs >= max_ref) {
         int oldest = -1;
         for (int i = 0; i < d->nrefs; i++)
            if (!d->refs[i].long_term && (oldest < 0 || d->refs[i].frame_num_wrap < d->refs[oldest].frame_num_wrap))
               oldest = i;
         if (oldest >= 0)
            remove_ref(d, oldest);
      }
   }
   if (d->prev_has_mmco5) {
      // 8.2.1：MMCO5 之後，目前畫面視為 frame_num 0、POC 減去自己的 TopFieldOrderCnt（frame）
      const int32_t temp = cur.top_poc < cur.bottom_poc ? cur.top_poc : cur.bottom_poc;
      cur.top_poc -= temp;
      cur.bottom_poc -= temp;
      cur.frame_num = 0;
      cur.frame_num_wrap = 0;
      d->prev_poc_msb = 0;
      d->prev_poc_lsb = cur.top_poc;
      d->prev_frame_num = 0;
      d->prev_frame_num_offset = 0;
      d->group_bump = 1;
   }
   cur.long_term = cur_long;
   if (d->nrefs < 16)
      d->refs[d->nrefs++] = cur;
}
