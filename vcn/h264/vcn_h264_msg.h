// SPDX-License-Identifier: MIT
// VCN 解碼 message 的結構與組裝。結構定義照 Mesa src/amd/common/ac_vcn_dec.h（MIT，Copyright Advanced Micro Devices, Inc.），
// 組裝邏輯照 Mesa ac_vcn_dec.c 的 vcn_build_decode_cmd() / build_avc_msg()（TIER0：DPB 是一整塊由韌體管理）
// 與 radeonsi si_video_dec.c 的 si_dec_h264()。查看時的 Mesa 版本：chaotic-cx/mesa-mirror daf55d3（2026-11-24）。
#ifndef FW13_VCN_H264_MSG_H
#define FW13_VCN_H264_MSG_H

#include <stdint.h>

#include "h264_parse.h"

#define RDECODE_MSG_CREATE 0
#define RDECODE_MSG_DECODE 1
#define RDECODE_MSG_DESTROY 2
#define RDECODE_CODEC_H264_PERF 7
#define RDECODE_MESSAGE_CREATE 1
#define RDECODE_MESSAGE_DECODE 2
#define RDECODE_MESSAGE_AVC 6
#define RDECODE_SESSION_CONTEXT_SIZE (128 * 1024)
#define RDECODE_ARRAY_MODE_ADDRLIB_SEL_GFX11 3   // VCN 4.0.x（ac_vcn_create_video_decoder）
#define RDECODE_H264_PROFILE_BASELINE 0
#define RDECODE_H264_PROFILE_MAIN 1
#define RDECODE_H264_PROFILE_HIGH 2

typedef struct {
   uint32_t message_id, offset, size, filled;
} rvcn_dec_message_index_t;

typedef struct {
   uint32_t header_size, total_size, num_buffers, msg_type, stream_handle, status_report_feedback_number;
   rvcn_dec_message_index_t index[1];
} rvcn_dec_message_header_t;

typedef struct {
   uint32_t stream_type, decode_flags, width_in_samples, height_in_samples;
   uint32_t bsd_size, dpb_size, dt_size, sct_size, sc_coeff_size, hw_ctxt_size, sw_ctxt_size, pic_param_size, mb_cntl_size;
   uint32_t reserved0[4];
   uint32_t decode_buffer_flags;
   uint32_t db_pitch, db_aligned_height, db_tiling_mode, db_swizzle_mode, db_array_mode, db_field_mode, db_surf_tile_config;
   uint32_t dt_pitch, dt_uv_pitch, dt_tiling_mode, dt_swizzle_mode, dt_array_mode, dt_field_mode, dt_out_format;
   uint32_t dt_surf_tile_config, dt_uv_surf_tile_config;
   uint32_t dt_luma_top_offset, dt_luma_bottom_offset, dt_chroma_top_offset, dt_chroma_bottom_offset;
   uint32_t dt_chromaV_top_offset, dt_chromaV_bottom_offset;
   uint32_t mif_wrc_en, db_pitch_uv;
   uint8_t reserved1[20];
} rvcn_dec_message_decode_t;

typedef struct {
   uint16_t viewOrderIndex, viewId;
   uint16_t numOfAnchorRefsInL0, viewIdOfAnchorRefsInL0[15];
   uint16_t numOfAnchorRefsInL1, viewIdOfAnchorRefsInL1[15];
   uint16_t numOfNonAnchorRefsInL0, viewIdOfNonAnchorRefsInL0[15];
   uint16_t numOfNonAnchorRefsInL1, viewIdOfNonAnchorRefsInL1[15];
} radeon_mvcElement_t;

typedef struct {
   uint32_t profile, level, sps_info_flags, pps_info_flags;
   uint8_t chroma_format, bit_depth_luma_minus8, bit_depth_chroma_minus8, log2_max_frame_num_minus4;
   uint8_t pic_order_cnt_type, log2_max_pic_order_cnt_lsb_minus4, num_ref_frames, reserved_8bit;
   int8_t pic_init_qp_minus26, pic_init_qs_minus26, chroma_qp_index_offset, second_chroma_qp_index_offset;
   uint8_t num_slice_groups_minus1, slice_group_map_type, num_ref_idx_l0_active_minus1, num_ref_idx_l1_active_minus1;
   uint16_t slice_group_change_rate_minus1, reserved_16bit_1;
   uint8_t scaling_list_4x4[6][16];
   uint8_t scaling_list_8x8[2][64];
   uint32_t frame_num;
   uint32_t frame_num_list[16];
   int32_t curr_field_order_cnt_list[2];
   int32_t field_order_cnt_list[16][2];
   uint32_t decoded_pic_idx, curr_pic_ref_frame_num;
   uint8_t ref_frame_list[16];
   uint32_t reserved[122];
   struct {
      uint32_t numViews, viewId0;
      radeon_mvcElement_t mvcElements[1];
   } mvc;
   uint16_t non_existing_frame_flags;
   uint32_t used_for_reference_flags;
} rvcn_dec_message_avc_t;

typedef struct {
   uint8_t scaling_list_4x4[6][16];
   uint8_t scaling_list_8x8[2][64];
} rvcn_dec_avc_its_t;

// 一個 session 的尺寸與 buffer 大小（TIER0）
typedef struct {
   uint32_t width, height;        // 解碼尺寸（MB 對齊）
   uint32_t max_num_ref;          // Mesa：max_references + 1
   uint32_t dpb_size, hw_ctx_size;
   uint32_t db_pitch, db_pitch_uv, db_aligned_height;
   uint32_t dt_pitch, dt_height;  // 輸出 NV12（線性）
   uint32_t dt_size;              // Y + UV
} vcn_h264_layout;

void vcn_h264_layout_init(vcn_h264_layout *l, const h264_sps *sps);

// 每張畫面的參考資訊（第一版只做 IDR：沒有參考畫面）
typedef struct {
   int32_t top_poc, bottom_poc;
   uint32_t decoded_pic_idx;       // 這張畫面在 DPB 的 slot
   uint32_t num_refs;
   uint8_t ref_idx[16];            // 參考畫面的 DPB slot（0xff = 沒有）
   uint32_t ref_frame_num[16];
   int32_t ref_poc[16][2];
   uint16_t long_term_flags;
   uint32_t used_for_reference_flags;
} vcn_h264_pic;

// 組 create / destroy message，回傳 dword 數
uint32_t vcn_h264_session_msg(uint32_t *w, int destroy, uint32_t handle, const vcn_h264_layout *l);
// 組 decode message（header + decode + avc），回傳 byte 數；its 填 IT scaling buffer
uint32_t vcn_h264_decode_msg(uint8_t *msg, rvcn_dec_avc_its_t *its, uint32_t handle, const vcn_h264_layout *l,
                             const h264_sps *sps, const h264_pps *pps, const h264_slice *first_slice,
                             const vcn_h264_pic *pic, uint32_t bsd_size);

// libdrm 向量那張 864×480 畫面的 SPS／PPS（向量沒有 SPS／PPS NAL，參數從 avc 結構反推，test_h264.c 驗證過逐 byte 相同）
void vcn_h264_libdrm_params(h264_sps *sps, h264_pps *pps);

#endif
