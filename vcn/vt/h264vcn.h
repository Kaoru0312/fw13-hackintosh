// SPDX-License-Identifier: Apache-2.0
// H.264 解碼 session：avcC／長度前綴 NAL → 我們的 parser＋DPB＋message 產生器 → PhxBringup selector 130 → CVPixelBuffer（NV12）。
// VideoToolbox 外掛（H264VCNDecoder.c）和命令列測試共用。
#ifndef FW13_H264VCN_H
#define FW13_H264VCN_H

#include <CoreVideo/CoreVideo.h>
#include <stdint.h>

typedef struct H264Vcn H264Vcn;

enum {
   H264VCN_OK = 0,
   H264VCN_UNSUPPORTED = 1,   // 這個串流不支援（field、10-bit、4:2:2、太大……）：讓 VideoToolbox 換別的解碼器
   H264VCN_NOT_AVAILABLE = 2, // kext 太舊、VCN 沒帶起來、別的 session 正在用
   H264VCN_BAD_DATA = 3,
   H264VCN_DEVICE = 4,        // kext／VCN 出錯（逾時等）：session 不能再用
   H264VCN_MEMORY = 5,
};

typedef struct {
   uint32_t group;   // 每個 IDR／MMCO5 加 1
   int32_t poc;      // 同一群組內依 POC 排序就是顯示順序
   int reorder;      // 這個串流需要的重排深度（SPS 的 max_num_ref_frames，保守值）
} H264VcnOrder;

// avcC（ISO/IEC 14496-15 AVCDecoderConfigurationRecord）。失敗時回 NULL，*why 是 H264VCN_*，msg 寫原因。
H264Vcn *h264vcn_create(const uint8_t *avcC, size_t len, int *why, char *msg, size_t msglen);
void h264vcn_destroy(H264Vcn *v);
// 解一個 sample（一張畫面的長度前綴 NAL）。成功回 0、*out 是 retain 過的 CVPixelBuffer（caller release）。
int h264vcn_decode(H264Vcn *v, const uint8_t *sample, size_t len, CVPixelBufferRef *out, H264VcnOrder *order);
const char *h264vcn_last_error(const H264Vcn *v);
// 輸出的尺寸（裁切後）
void h264vcn_size(const H264Vcn *v, int32_t *w, int32_t *h);
CFDictionaryRef h264vcn_copy_pixel_buffer_attributes(const H264Vcn *v);
// 統計：kext 回報的 VCN 時間（µs）
uint32_t h264vcn_last_vcn_us(const H264Vcn *v);
// 用哪條路開的 kext client（log 用）
const char *h264vcn_path(const H264Vcn *v);

#endif
