// SPDX-License-Identifier: MIT
// 見 vcn_h264_msg.h 的出處說明。
#include "vcn_h264_msg.h"

#include <string.h>

_Static_assert(sizeof(rvcn_dec_message_header_t) == 40, "header");
_Static_assert(sizeof(rvcn_dec_message_decode_t) == 188, "decode");   // Mesa 現行版；libdrm 向量是舊版 180（0xb4），少了 reserved1 的 8 bytes
_Static_assert(sizeof(rvcn_dec_avc_its_t) == 224, "its");             // libdrm 向量的 scaling table 224 bytes

static uint32_t align(uint32_t v, uint32_t a) { return (v + a - 1) / a * a; }

void vcn_h264_layout_init(vcn_h264_layout *l, const h264_sps *sps)
{
   memset(l, 0, sizeof *l);
   const uint32_t map_units = sps->pic_height_in_map_units_minus1 + 1;
   l->width = (sps->pic_width_in_mbs_minus1 + 1) * 16;
   l->height = map_units * (sps->frame_mbs_only_flag ? 1 : 2) * 16;
   l->max_num_ref = (sps->max_num_ref_frames ? sps->max_num_ref_frames : 1) + 1;
   if (l->max_num_ref > 17)
      l->max_num_ref = 17;

   // ac_vcn_dec_dpb_size()：AVC、VCN 2..4 的 dpb_alignment 是 32
   const uint32_t w = align(l->width, 16), h = align(l->height, 16);
   uint32_t image = align(w, 32) * align(h, 32);
   image = align(image + image / 2, 1024);
   l->dpb_size = image * l->max_num_ref;

   // calc_ctx_size_avc()
   const uint32_t wmb = w / 16, hmb = align(h / 16, 2);
   l->hw_ctx_size = l->max_num_ref * align(wmb * hmb * 192, 256);

   // TIER0：vcn_build_decode_cmd()
   l->db_pitch = align(l->width, 32);
   l->db_pitch_uv = align(l->width / 2, 32);
   l->db_aligned_height = align(l->height, 64);

   // 輸出：線性 NV12，行距對齊 256 bytes（libdrm 向量 864 寬用 1024 行距）
   l->dt_pitch = align(l->width, 256);
   l->dt_height = l->height;
   l->dt_size = l->dt_pitch * l->dt_height * 3 / 2;
}

uint32_t vcn_h264_session_msg(uint32_t *w, int destroy, uint32_t handle, const vcn_h264_layout *l)
{
   memset(w, 0, 14 * 4);
   w[0] = 40;
   w[1] = destroy ? 24 : 56;
   w[2] = destroy ? 0 : 1;
   w[3] = destroy ? RDECODE_MSG_DESTROY : RDECODE_MSG_CREATE;
   w[4] = handle;
   w[5] = 0;
   if (destroy)
      return 6;
   w[6] = RDECODE_MESSAGE_CREATE;
   w[7] = 40;
   w[8] = 16;
   w[9] = 0;
   w[10] = RDECODE_CODEC_H264_PERF;
   w[11] = 0;
   w[12] = l->width;
   w[13] = l->height;
   return 14;
}

uint32_t vcn_h264_decode_msg(uint8_t *msg, rvcn_dec_avc_its_t *its, uint32_t handle, const vcn_h264_layout *l,
                             const h264_sps *sps, const h264_pps *pps, const h264_slice *sl, const vcn_h264_pic *pic,
                             uint32_t bsd_size)
{
   // 版面：header（含 index[0]）| index（codec）| decode | avc。decode @0x38 跟 libdrm 向量一樣；avc @0xf4
   //（向量是 @0xec：它用舊版 180 bytes 的 decode 結構，Mesa 現行版 188 bytes）
   const uint32_t off_index_codec = sizeof(rvcn_dec_message_header_t);
   const uint32_t off_decode = off_index_codec + sizeof(rvcn_dec_message_index_t);
   const uint32_t off_codec = off_decode + sizeof(rvcn_dec_message_decode_t);
   memset(msg, 0, off_codec + sizeof(rvcn_dec_message_avc_t));

   rvcn_dec_message_header_t *hdr = (rvcn_dec_message_header_t *)msg;
   rvcn_dec_message_index_t *idx = (rvcn_dec_message_index_t *)(msg + off_index_codec);
   rvcn_dec_message_decode_t *d = (rvcn_dec_message_decode_t *)(msg + off_decode);
   rvcn_dec_message_avc_t *a = (rvcn_dec_message_avc_t *)(msg + off_codec);

   hdr->header_size = sizeof(rvcn_dec_message_header_t);
   hdr->msg_type = RDECODE_MSG_DECODE;
   hdr->stream_handle = handle;
   hdr->status_report_feedback_number = 1;   // libdrm 向量是 1（Mesa 沒設）
   hdr->index[0].message_id = RDECODE_MESSAGE_DECODE;
   hdr->index[0].offset = off_decode;
   hdr->index[0].size = sizeof(rvcn_dec_message_decode_t);
   idx->message_id = RDECODE_MESSAGE_AVC;
   idx->offset = off_codec;
   idx->size = sizeof(rvcn_dec_message_avc_t);
   hdr->num_buffers = 2;
   hdr->total_size = off_codec + sizeof(rvcn_dec_message_avc_t);

   d->stream_type = RDECODE_CODEC_H264_PERF;
   d->width_in_samples = l->width;
   d->height_in_samples = l->height;
   d->bsd_size = bsd_size;
   d->dpb_size = l->dpb_size;
   d->dt_size = l->dt_size;
   d->hw_ctxt_size = l->hw_ctx_size;
   d->sw_ctxt_size = RDECODE_SESSION_CONTEXT_SIZE;
   d->db_pitch = l->db_pitch;
   d->db_pitch_uv = l->db_pitch_uv;
   d->db_aligned_height = l->db_aligned_height;
   d->db_array_mode = RDECODE_ARRAY_MODE_ADDRLIB_SEL_GFX11;
   d->dt_pitch = l->dt_pitch;
   d->dt_uv_pitch = l->dt_pitch / 2;   // UV 平面的元素是 2 bytes（libdrm：1024 / 512）
   d->dt_array_mode = RDECODE_ARRAY_MODE_ADDRLIB_SEL_GFX11;
   d->dt_swizzle_mode = 0;             // 線性
   d->dt_luma_top_offset = 0;
   d->dt_chroma_top_offset = l->dt_pitch * l->dt_height;
   d->mif_wrc_en = 1;                  // VCN 3.0 以上

   // build_avc_msg()
   a->sps_info_flags = (uint32_t)sps->direct_8x8_inference_flag << 0 | (uint32_t)sps->mb_adaptive_frame_field_flag << 1 |
                       (uint32_t)sps->frame_mbs_only_flag << 2 | (uint32_t)sps->delta_pic_order_always_zero_flag << 3 |
                       (uint32_t)sps->gaps_in_frame_num_value_allowed_flag << 5 | 1u << 7;   // EXTENSION_SUPPORT（tier < 2）
   a->pps_info_flags = (uint32_t)pps->transform_8x8_mode_flag << 0 | (uint32_t)pps->redundant_pic_cnt_present_flag << 1 |
                       (uint32_t)pps->constrained_intra_pred_flag << 2 |
                       (uint32_t)pps->deblocking_filter_control_present_flag << 3 | (uint32_t)pps->weighted_bipred_idc << 4 |
                       (uint32_t)pps->weighted_pred_flag << 6 |
                       (uint32_t)pps->bottom_field_pic_order_in_frame_present_flag << 7 |
                       (uint32_t)pps->entropy_coding_mode_flag << 8;
   switch (sps->profile_idc) {
   case 66: a->profile = RDECODE_H264_PROFILE_BASELINE; break;
   case 77: a->profile = RDECODE_H264_PROFILE_MAIN; break;
   default: a->profile = RDECODE_H264_PROFILE_HIGH; break;   // 100 以上都當 High（Mesa 只接受 66/77/100）
   }
   a->level = sps->level_idc;
   a->chroma_format = sps->chroma_format_idc;
   a->bit_depth_luma_minus8 = sps->bit_depth_luma_minus8;
   a->bit_depth_chroma_minus8 = sps->bit_depth_chroma_minus8;
   a->log2_max_frame_num_minus4 = sps->log2_max_frame_num_minus4;
   a->pic_order_cnt_type = sps->pic_order_cnt_type;
   a->log2_max_pic_order_cnt_lsb_minus4 = sps->log2_max_pic_order_cnt_lsb_minus4;
   a->num_ref_frames = sps->max_num_ref_frames;
   a->pic_init_qp_minus26 = pps->pic_init_qp_minus26;
   a->pic_init_qs_minus26 = pps->pic_init_qs_minus26;
   a->chroma_qp_index_offset = pps->chroma_qp_index_offset;
   a->second_chroma_qp_index_offset = pps->second_chroma_qp_index_offset;
   a->num_slice_groups_minus1 = pps->num_slice_groups_minus1;
   a->slice_group_map_type = pps->slice_group_map_type;
   // radeonsi 把 VA 的 num_ref_idx_l*_active_minus1（slice 層級）傳進這兩個欄位
   a->num_ref_idx_l0_active_minus1 = sl->num_ref_idx_l0_active_minus1;
   a->num_ref_idx_l1_active_minus1 = sl->num_ref_idx_l1_active_minus1;
   a->slice_group_change_rate_minus1 = pps->slice_group_change_rate_minus1;
   // libdrm 向量把 scaling list 也放在 avc 結構裡（Mesa 只放 IT buffer）；兩邊都填
   memcpy(a->scaling_list_4x4, pps->scaling_list_4x4, sizeof a->scaling_list_4x4);
   memcpy(a->scaling_list_8x8[0], pps->scaling_list_8x8[0], 64);
   memcpy(a->scaling_list_8x8[1], pps->scaling_list_8x8[1], 64);
   memcpy(its->scaling_list_4x4, pps->scaling_list_4x4, sizeof its->scaling_list_4x4);
   memcpy(its->scaling_list_8x8[0], pps->scaling_list_8x8[0], 64);
   memcpy(its->scaling_list_8x8[1], pps->scaling_list_8x8[1], 64);

   a->frame_num = sl->frame_num;
   a->curr_field_order_cnt_list[0] = pic->top_poc;
   a->curr_field_order_cnt_list[1] = pic->bottom_poc;
   a->decoded_pic_idx = pic->decoded_pic_idx;
   a->curr_pic_ref_frame_num = pic->num_refs;
   a->used_for_reference_flags = pic->used_for_reference_flags;
   for (int i = 0; i < 16; i++) {
      a->ref_frame_list[i] = pic->ref_idx[i];
      if (pic->ref_idx[i] != 0xff) {
         a->frame_num_list[i] = pic->ref_frame_num[i];
         a->field_order_cnt_list[i][0] = pic->ref_poc[i][0];
         a->field_order_cnt_list[i][1] = pic->ref_poc[i][1];
         if (pic->long_term_flags & (1u << i))
            a->ref_frame_list[i] |= 0x80;
      }
   }
   return hdr->total_size;
}

void vcn_h264_libdrm_params(h264_sps *s, h264_pps *p)
{
   memset(s, 0, sizeof *s);
   memset(p, 0, sizeof *p);
   s->valid = p->valid = 1;
   s->profile_idc = 100;
   s->level_idc = 30;
   s->chroma_format_idc = 1;
   s->direct_8x8_inference_flag = 1;
   s->frame_mbs_only_flag = 1;
   s->log2_max_frame_num_minus4 = 1;
   s->log2_max_pic_order_cnt_lsb_minus4 = 3;
   s->max_num_ref_frames = 2;
   s->pic_width_in_mbs_minus1 = 53;
   s->pic_height_in_map_units_minus1 = 29;
   p->pic_init_qp_minus26 = 2;
   p->deblocking_filter_control_present_flag = 1;
   p->bottom_field_pic_order_in_frame_present_flag = 1;
   memset(p->scaling_list_4x4, 16, sizeof p->scaling_list_4x4);
   memset(p->scaling_list_8x8, 16, sizeof p->scaling_list_8x8);
}
