// SPDX-License-Identifier: Apache-2.0
// MD5（RFC 1321），用來跟 ffmpeg -f framemd5 的結果比對。
#ifndef FW13_MD5_H
#define FW13_MD5_H
#include <stddef.h>
#include <stdint.h>
typedef struct { uint32_t s[4]; uint64_t n; uint8_t buf[64]; } md5_ctx;
void md5_init(md5_ctx *c);
void md5_update(md5_ctx *c, const void *data, size_t len);
void md5_final(md5_ctx *c, uint8_t out[16]);
#endif
