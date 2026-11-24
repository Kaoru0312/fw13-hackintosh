// SPDX-License-Identifier: Apache-2.0
// H.264 解碼端的 POC 計算（8.2.1）與參考畫面標記（8.2.5），只支援 frame（frame_mbs_only_flag = 1，沒有 field／MBAFF）。
// 產出 VCN decode message 需要的參考清單（vcn_h264_pic），以及每張畫面用的 DPB slot。
#ifndef FW13_H264_DPB_H
#define FW13_H264_DPB_H

#include "h264_parse.h"
#include "vcn_h264_msg.h"

#define H264_DPB_SLOTS 17   // radeonsi render_pic_list：ARRAY_SIZE(pic->ref) + 1

typedef struct {
   int used;           // 1 = 被當參考（short 或 long）
   int long_term;
   uint32_t frame_num;
   int32_t frame_num_wrap;
   uint32_t long_term_frame_idx;
   int32_t top_poc, bottom_poc;
   uint32_t slot;
} h264_ref;

typedef struct {
   h264_ref refs[16];
   int nrefs;
   int max_long_term_frame_idx;   // -1 = no long-term frame indices
   // POC 狀態
   int32_t prev_poc_msb, prev_poc_lsb;          // type 0
   int32_t prev_frame_num_offset;               // type 1／2
   uint32_t prev_frame_num;
   int prev_has_mmco5;                          // 目前這張畫面的標記裡有 MMCO5（h264_dpb_end 設定）
   int group_bump;                              // 下一張畫面開新的排序群組
   uint32_t max_slots;                          // 可用的 slot 數（= layout.max_num_ref）
   uint32_t pic_count;                          // 從上一個 IDR／MMCO5 起的畫面數（排序用的群組編號在 group）
   uint32_t group;                              // 每遇到 IDR 或 MMCO5 加 1：同一群組內依 POC 排序就是顯示順序
} h264_dpb;

typedef struct {
   uint32_t group;
   int32_t poc;          // min(top, bottom)
} h264_out_info;

void h264_dpb_init(h264_dpb *d, uint32_t max_slots);
// 開始一張新畫面：算 POC、挑 slot、填 pic（參考清單是「目前所有參考畫面」，跟 VA-API ReferenceFrames 一樣）。回傳 0 成功。
int h264_dpb_begin(h264_dpb *d, const h264_sps *sps, const h264_slice *first, vcn_h264_pic *pic, h264_out_info *out);
// 畫面解完：依 nal_ref_idc／MMCO／sliding window 更新參考標記。
void h264_dpb_end(h264_dpb *d, const h264_sps *sps, const h264_slice *first, const vcn_h264_pic *pic);

#endif
