// SPDX-License-Identifier: Apache-2.0
// H.264 Annex B 解析：SPS、PPS、slice header（ITU-T H.264 7.3.2.1.1、7.3.2.2、7.3.3）。
// 只解 VCN 解碼需要的欄位；slice data 交給 VCN 韌體自己解（stream type 7 = H264_PERF）。
#ifndef FW13_H264_PARSE_H
#define FW13_H264_PARSE_H

#include <stddef.h>
#include <stdint.h>

#define H264_MAX_SPS 32
#define H264_MAX_PPS 256

typedef struct {
   int valid;
   uint8_t profile_idc, constraint_flags, level_idc, sps_id;
   uint8_t chroma_format_idc, separate_colour_plane_flag;
   uint8_t bit_depth_luma_minus8, bit_depth_chroma_minus8;
   uint8_t qpprime_y_zero_transform_bypass_flag;
   uint8_t seq_scaling_matrix_present_flag;
   uint8_t scaling_list_4x4[6][16];   // 光柵順序（raster order）
   uint8_t scaling_list_8x8[6][64];
   uint8_t log2_max_frame_num_minus4;
   uint8_t pic_order_cnt_type;
   uint8_t log2_max_pic_order_cnt_lsb_minus4;
   uint8_t delta_pic_order_always_zero_flag;
   int32_t offset_for_non_ref_pic, offset_for_top_to_bottom_field;
   uint8_t num_ref_frames_in_pic_order_cnt_cycle;
   int32_t offset_for_ref_frame[256];
   uint8_t max_num_ref_frames;
   uint8_t gaps_in_frame_num_value_allowed_flag;
   uint32_t pic_width_in_mbs_minus1, pic_height_in_map_units_minus1;
   uint8_t frame_mbs_only_flag, mb_adaptive_frame_field_flag, direct_8x8_inference_flag;
   uint8_t frame_cropping_flag;
   uint32_t crop_left, crop_right, crop_top, crop_bottom;
} h264_sps;

typedef struct {
   int valid;
   uint8_t pps_id, sps_id;
   uint8_t entropy_coding_mode_flag, bottom_field_pic_order_in_frame_present_flag;
   uint8_t num_slice_groups_minus1, slice_group_map_type;
   uint16_t slice_group_change_rate_minus1;
   uint8_t num_ref_idx_l0_default_active_minus1, num_ref_idx_l1_default_active_minus1;
   uint8_t weighted_pred_flag, weighted_bipred_idc;
   int8_t pic_init_qp_minus26, pic_init_qs_minus26, chroma_qp_index_offset, second_chroma_qp_index_offset;
   uint8_t deblocking_filter_control_present_flag, constrained_intra_pred_flag, redundant_pic_cnt_present_flag;
   uint8_t transform_8x8_mode_flag;
   uint8_t scaling_list_4x4[6][16];   // 已套用 fall-back 規則後的最終值（光柵順序）
   uint8_t scaling_list_8x8[6][64];
} h264_pps;

typedef struct {
   uint8_t idc;          // memory_management_control_operation
   uint32_t a, b;        // difference_of_pic_nums_minus1 / long_term_pic_num / long_term_frame_idx …（依 idc）
} h264_mmco;

typedef struct {
   uint8_t nal_unit_type, nal_ref_idc;
   uint32_t first_mb_in_slice;
   uint8_t slice_type;   // 0..4（已 mod 5）
   uint8_t pps_id;
   uint32_t frame_num;
   uint8_t field_pic_flag, bottom_field_flag;
   uint32_t idr_pic_id;
   uint32_t pic_order_cnt_lsb;
   int32_t delta_pic_order_cnt_bottom;
   int32_t delta_pic_order_cnt[2];
   uint8_t num_ref_idx_l0_active_minus1, num_ref_idx_l1_active_minus1;
   uint8_t no_output_of_prior_pics_flag, long_term_reference_flag;
   uint8_t adaptive_ref_pic_marking_mode_flag;
   uint8_t num_mmco;
   h264_mmco mmco[32];
} h264_slice;

typedef struct {
   h264_sps sps[H264_MAX_SPS];
   h264_pps pps[H264_MAX_PPS];
} h264_params;

// Annex B：找下一個 NAL（不含 start code）。回傳 NAL 起點，*len 是長度；找不到回 NULL。*next 指向下一次搜尋的位置。
const uint8_t *h264_next_nal(const uint8_t *buf, size_t size, size_t *pos, size_t *len);

// 以下都吃「含 NAL header 的原始 NAL」（尚未去除 emulation prevention），成功回 0。
int h264_parse_sps(h264_params *p, const uint8_t *nal, size_t len);
int h264_parse_pps(h264_params *p, const uint8_t *nal, size_t len);
int h264_parse_slice(const h264_params *p, const uint8_t *nal, size_t len, h264_slice *s);

#endif
