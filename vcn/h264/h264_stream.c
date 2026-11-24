// SPDX-License-Identifier: Apache-2.0
#include "h264_stream.h"
#include <string.h>

void h264_stream_init(h264_stream *s, const uint8_t *buf, size_t size)
{
   memset(s, 0, sizeof *s);
   s->buf = buf;
   s->size = size;
}

int h264_stream_next(h264_stream *s, h264_picture *pic, uint8_t *bs, uint32_t cap)
{
   memset(pic, 0, sizeof *pic);
   for (;;) {
      size_t before = s->pos, len;
      const uint8_t *nal = h264_next_nal(s->buf, s->size, &s->pos, &len);
      if (!nal)
         return pic->nslices ? 1 : 0;
      if (!len)
         continue;
      int t = nal[0] & 31;
      if (t == 7 || t == 8 || t == 9 || t == 11) {
         if (pic->nslices) {   // 下一張畫面的開頭（SPS／PPS／AUD／end of stream）
            s->pos = before;
            return 1;
         }
         if (t == 7 && h264_parse_sps(&s->ps, nal, len))
            return -1;
         if (t == 8 && h264_parse_pps(&s->ps, nal, len))
            return -2;
         continue;
      }
      if (t != 1 && t != 5)
         continue;   // SEI 等
      h264_slice sl;
      if (h264_parse_slice(&s->ps, nal, len, &sl))
         return -3;
      if (pic->nslices && sl.first_mb_in_slice == 0) {
         s->pos = before;
         return 1;
      }
      if (!pic->nslices)
         pic->first = sl;
      if (pic->bsd + 3 + len > cap)
         return -4;
      bs[pic->bsd++] = 0;
      bs[pic->bsd++] = 0;
      bs[pic->bsd++] = 1;
      memcpy(bs + pic->bsd, nal, len);
      pic->bsd += (uint32_t)len;
      pic->nslices++;
   }
}
