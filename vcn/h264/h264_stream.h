// SPDX-License-Identifier: Apache-2.0
// 把 Annex B 串流切成一張一張畫面（access unit）：遇到 SPS／PPS 就解析，slice 依 first_mb_in_slice == 0 分畫面。
#ifndef FW13_H264_STREAM_H
#define FW13_H264_STREAM_H
#include "h264_parse.h"

typedef struct {
   const uint8_t *buf;
   size_t size, pos;
   h264_params ps;
} h264_stream;

typedef struct {
   h264_slice first;        // 第一個 slice 的 header
   int nslices;
   uint32_t bsd;            // bitstream 長度（含每個 slice 前面的 00 00 01）
} h264_picture;

void h264_stream_init(h264_stream *s, const uint8_t *buf, size_t size);
// 下一張畫面的 slice 依序（加 start code）寫進 bs（容量 cap）。回傳 1 = 有畫面、0 = 結束、負數 = 錯誤。
int h264_stream_next(h264_stream *s, h264_picture *pic, uint8_t *bs, uint32_t cap);
#endif
